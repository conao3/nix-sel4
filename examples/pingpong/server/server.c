#include <stdint.h>
#include <microkit.h>

uintptr_t shared_vaddr;
uint64_t client_channel;

void init(void)
{
    microkit_dbg_puts("server: waiting for a notification\n");
}

void notified(microkit_channel ch)
{
    if (ch != (microkit_channel)client_channel) {
        microkit_dbg_puts("server: notification on an unexpected channel\n");
        return;
    }

    microkit_dbg_puts("server: received \"");
    microkit_dbg_puts((const char *)shared_vaddr);
    microkit_dbg_puts("\"\n");
}
