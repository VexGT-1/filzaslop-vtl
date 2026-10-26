#ifndef SandboxExtIssue_h
#define SandboxExtIssue_h

#import <Foundation/Foundation.h>

// Issue and consume a read-write sandbox extension token for a single path.
// Returns YES if the token was issued and consumed successfully.
BOOL SandboxExtIssuePath(NSString *path);

// Issue tokens for a broad set of common paths at startup.
void SandboxExtIssuePaths(void);

#endif
