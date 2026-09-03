#include <stdint.h>
#include <microkit.h>

/* Both symbols are patched by the microkit tool from the system description.
 * setvar targets are word sized, so the channel id is declared as uint64_t. */
uintptr_t shared_vaddr;
uint64_t server_channel;

static void copy_string(char *dst, const char *src)
{
    while ((*dst++ = *src++) != '\0') {
    }
}

void init(void)
{
    microkit_dbg_puts("client: writing into the shared region\n");
    copy_string((char *)shared_vaddr, "ping from the client");
    microkit_notify((microkit_channel)server_channel);
}

void notified(microkit_channel ch)
{
}
