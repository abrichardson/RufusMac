#include "MacusDiskAccess.h"
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/disk.h>
#include <sys/ioctl.h>
#include <spawn.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
extern char **environ;

// authopen is Apple's authorization-based disk opener. The descriptor is
// returned to the app; no AppleScript-root shell writes the device.
int macus_authorized_open(const char *path, const void *authorization, size_t authorization_size) {
    int sockets[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0) return -1;
    int yes = 1;
    setsockopt(sockets[0], SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, sockets[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, sockets[1], STDIN_FILENO);
    posix_spawn_file_actions_addclose(&actions, sockets[0]);
    posix_spawn_file_actions_addclose(&actions, sockets[1]);
    char *argv[] = {"/usr/libexec/authopen", "-stdoutpipe", "-extauth", "-o", "2", (char *)path, NULL};
    pid_t pid;
    int error = posix_spawn(&pid, argv[0], &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(sockets[1]);
    if (error) { close(sockets[0]); errno = error; return -1; }
    size_t sent = 0;
    while (sent < authorization_size) {
        ssize_t n = write(sockets[0], (const char *)authorization + sent, authorization_size - sent);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        sent += (size_t)n;
    }
    char byte;
    struct iovec iov = { &byte, 1 };
    union { struct cmsghdr alignment; char bytes[CMSG_SPACE(sizeof(int))]; } control;
    memset(&control, 0, sizeof(control));
    struct msghdr message = {0};
    message.msg_iov = &iov;
    message.msg_iovlen = 1;
    message.msg_control = control.bytes;
    message.msg_controllen = sizeof(control.bytes);
    ssize_t received;
    do { received = recvmsg(sockets[0], &message, 0); } while (received < 0 && errno == EINTR);
    int fd = -1;
    if (received > 0 && !(message.msg_flags & MSG_CTRUNC)) {
        for (struct cmsghdr *c = CMSG_FIRSTHDR(&message); c; c = CMSG_NXTHDR(&message, c)) {
            if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS && c->cmsg_len >= CMSG_LEN(sizeof(int))) {
                memcpy(&fd, CMSG_DATA(c), sizeof(fd));
                break;
            }
        }
    }
    close(sockets[0]);
    int status;
    while (waitpid(pid, &status, 0) < 0) { if (errno != EINTR) { status = -1; break; } }
    if (status == -1 || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        if (fd >= 0) close(fd);
        errno = EACCES;
        return -1;
    }
    if (fd < 0) { errno = EACCES; return -1; }
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    return fd;
}

int macus_device_size(int fd, uint64_t *size) {
    uint64_t blocks;
    uint32_t block_size;
    if (ioctl(fd, DKIOCGETBLOCKCOUNT, &blocks) || ioctl(fd, DKIOCGETBLOCKSIZE, &block_size)) return -1;
    if (!block_size || blocks > UINT64_MAX / block_size) { errno = EOVERFLOW; return -1; }
    *size = blocks * block_size;
    return 0;
}
