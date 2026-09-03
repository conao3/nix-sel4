{ lib }:

# Renders a Microkit system description (XML) from a Nix attribute set.
#
# Addresses and sizes are plain Nix integers; they are rendered as hexadecimal.
# Channel and IRQ identifiers are allocated automatically per protection domain
# unless given explicitly.
{
  # name -> { size, pageSize ? null, physAddr ? null }
  memoryRegions ? { },
  # name -> {
  #   programImage,
  #   priority ? null, budget ? null, period ? null, passive ? null,
  #   stackSize ? null, cpu ? null, domain ? null,
  #   maps ? [ { mr, vaddr, perms ? "rw", cached ? null, setvarVaddr ? null } ],
  #   irqs ? [ { irq, id ? null, trigger ? null, setvarId ? null } ],
  # }
  protectionDomains,
  # [ { ends = [ "a" "b" ]; } ] or [ { ends = [ { pd = "a"; } { pd = "b"; pp = true; } ]; } ]
  channels ? [ ],
}:

let
  maxChannelId = 62;

  hex = n: "0x${lib.toHexString n}";

  attr =
    n: v:
    if v == null then
      ""
    else if lib.isBool v then
      " ${n}=\"${if v then "true" else "false"}\""
    else
      " ${n}=\"${toString v}\"";

  hexAttr = n: v: if v == null then "" else " ${n}=\"${hex v}\"";

  pdNames = lib.attrNames protectionDomains;
  mrNames = lib.attrNames memoryRegions;

  normEnd = e: if lib.isString e then { pd = e; } else e;

  # --- validation -----------------------------------------------------------

  checkMemoryRegion =
    name: mr:
    lib.throwIf (!(mr ? size)) "nix-sel4: memory region '${name}' に size がありません" (
      lib.throwIf (
        !lib.isInt mr.size
      ) "nix-sel4: memory region '${name}' の size は整数で書いてください (0x1000 は 4096)" true
    );

  checkMap =
    pdName: m:
    lib.throwIf (!(m ? mr)) "nix-sel4: PD '${pdName}' の map に mr がありません" (
      lib.throwIf (!lib.elem m.mr mrNames)
        "nix-sel4: PD '${pdName}' の map が未定義の memory region '${m.mr}' を参照しています"
        (
          lib.throwIf (
            !(m ? vaddr) || !lib.isInt m.vaddr
          ) "nix-sel4: PD '${pdName}' の map '${m.mr}' に整数の vaddr がありません" true
        )
    );

  # Detects overlapping mappings inside one protection domain.
  checkOverlap =
    pdName: maps:
    let
      spans = lib.sort (a: b: a.start < b.start) (
        map (m: {
          start = m.vaddr;
          end = m.vaddr + memoryRegions.${m.mr}.size;
          inherit (m) mr;
        }) maps
      );
      pairs = lib.zipListsWith (a: b: { inherit a b; }) (lib.take (lib.max 0 (
        lib.length spans - 1
      )) spans) (lib.drop 1 spans);
      bad = lib.filter (p: p.a.end > p.b.start) pairs;
    in
    lib.throwIf (bad != [ ]) (
      "nix-sel4: PD '${pdName}' の map が重なっています: "
      + lib.concatMapStringsSep ", " (
        p: "${p.a.mr} (${hex p.a.start}-${hex p.a.end}) と ${p.b.mr} (${hex p.b.start}-)"
      ) bad
    ) true;

  checkPd =
    name: pd:
    lib.throwIf (!(pd ? programImage)) "nix-sel4: PD '${name}' に programImage がありません" (
      lib.all lib.id (map (checkMap name) (pd.maps or [ ])) && checkOverlap name (pd.maps or [ ])
    );

  checkChannel =
    ch:
    let
      ends = map normEnd (ch.ends or [ ]);
      names = map (e: e.pd) ends;
      unknown = lib.subtractLists pdNames names;
    in
    lib.throwIf (lib.length ends != 2) "nix-sel4: channel の ends はちょうど 2 つ書いてください" (
      lib.throwIf (
        unknown != [ ]
      ) "nix-sel4: channel が未定義の PD ${lib.concatStringsSep ", " unknown} を参照しています" true
    );

  validated =
    lib.all lib.id (lib.mapAttrsToList checkMemoryRegion memoryRegions)
    && lib.all lib.id (lib.mapAttrsToList checkPd protectionDomains)
    && lib.all lib.id (map checkChannel channels);

  # --- channel id allocation ------------------------------------------------

  firstFree =
    used:
    let
      go = i: if lib.elem i used then go (i + 1) else i;
    in
    go 0;

  allocate =
    state: pdName: explicit:
    let
      used = state.${pdName} or [ ];
      id = if explicit != null then explicit else firstFree used;
    in
    lib.throwIf (id > maxChannelId)
      "nix-sel4: PD '${pdName}' の channel id が ${toString maxChannelId} を超えました"
      {
        inherit id;
        state = state // {
          ${pdName} = used ++ [ id ];
        };
      };

  irqPass =
    lib.foldl'
      (
        acc: pdName:
        let
          irqs = protectionDomains.${pdName}.irqs or [ ];
          r =
            lib.foldl'
              (
                a: irq:
                let
                  al = allocate a.state pdName (irq.id or null);
                in
                {
                  inherit (al) state;
                  out = a.out ++ [ (irq // { inherit (al) id; }) ];
                }
              )
              {
                inherit (acc) state;
                out = [ ];
              }
              irqs;
        in
        {
          inherit (r) state;
          irqs = acc.irqs // {
            ${pdName} = r.out;
          };
        }
      )
      {
        state = { };
        irqs = { };
      }
      pdNames;

  channelPass =
    lib.foldl'
      (
        acc: ch:
        let
          ends = map normEnd ch.ends;
          a = allocate acc.state (lib.elemAt ends 0).pd ((lib.elemAt ends 0).id or null);
          b = allocate a.state (lib.elemAt ends 1).pd ((lib.elemAt ends 1).id or null);
        in
        {
          inherit (b) state;
          out = acc.out ++ [
            [
              ((lib.elemAt ends 0) // { inherit (a) id; })
              ((lib.elemAt ends 1) // { inherit (b) id; })
            ]
          ];
        }
      )
      {
        inherit (irqPass) state;
        out = [ ];
      }
      channels;

  # --- rendering ------------------------------------------------------------

  renderMemoryRegion =
    name: mr:
    "    <memory_region name=\"${name}\"${hexAttr "size" mr.size}${
          hexAttr "page_size" (mr.pageSize or null)
        }${hexAttr "phys_addr" (mr.physAddr or null)} />";

  renderMap =
    m:
    "        <map mr=\"${m.mr}\"${hexAttr "vaddr" m.vaddr} perms=\"${m.perms or "rw"}\"${
              attr "cached" (m.cached or null)
            }${attr "setvar_vaddr" (m.setvarVaddr or null)} />";

  renderIrq =
    i:
    "        <irq irq=\"${toString i.irq}\" id=\"${toString i.id}\"${
              attr "trigger" (i.trigger or null)
            }${attr "setvar_id" (i.setvarId or null)} />";

  renderPd =
    name: pd:
    lib.concatStringsSep "\n" (
      [
        "    <protection_domain name=\"${name}\"${attr "priority" (pd.priority or null)}${
              attr "budget" (pd.budget or null)
            }${attr "period" (pd.period or null)}${attr "passive" (pd.passive or null)}${
              hexAttr "stack_size" (pd.stackSize or null)
            }${attr "cpu" (pd.cpu or null)}${attr "domain" (pd.domain or null)}>"
        "        <program_image path=\"${pd.programImage}\" />"
      ]
      ++ map renderMap (pd.maps or [ ])
      ++ map renderIrq irqPass.irqs.${name}
      ++ [ "    </protection_domain>" ]
    );

  renderEnd =
    e:
    "        <end pd=\"${e.pd}\" id=\"${toString e.id}\"${attr "pp" (e.pp or null)}${
              attr "notify" (e.notify or null)
            }${attr "setvar_id" (e.setvarId or null)} />";

  renderChannel =
    ends: lib.concatStringsSep "\n" ([ "    <channel>" ] ++ map renderEnd ends ++ [ "    </channel>" ]);

  document = lib.concatStringsSep "\n" (
    [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      "<!-- Generated by nix-sel4. Edit the Nix expression, not this file. -->"
      "<system>"
    ]
    ++ lib.mapAttrsToList renderMemoryRegion memoryRegions
    ++ lib.mapAttrsToList renderPd protectionDomains
    ++ map renderChannel channelPass.out
    ++ [
      "</system>"
      ""
    ]
  );
in
lib.seq validated document
