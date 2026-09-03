#include <stdint.h>
#include <microkit.h>

void init(void)
{
    microkit_dbg_puts("hello, world from nix-sel4\n");
}

void notified(microkit_channel ch)
{
}
