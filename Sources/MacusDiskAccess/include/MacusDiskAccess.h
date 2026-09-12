#include <stdint.h>
#include <stddef.h>
int macus_authorized_open(const char *path, const void *authorization, size_t authorization_size);
int macus_device_size(int fd, uint64_t *size);
