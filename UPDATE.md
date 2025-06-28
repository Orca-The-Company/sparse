# `sparse update` command
## Merge Detection
The `isMerged` function in `slice.zig` determines whether the current slice (a Git branch reference) has been merged into another branch (`into`). It uses Git operations to compare commit trees and logs, caching results for efficiency.

### Step-by-Step Breakdown
1. **Check Cache**
   If the merge status for the target branch is already cached in `_is_merge_into_map`, return the cached result.
2. **Quick Object ID Check**
   If the object IDs (commit hashes) of the two branches are the same, return `false` (no merge check needed).
3. **Find Merge Base**
   Use `GitMerge.base` to find the common ancestor commit (merge base) between the current slice and the target branch.
4. **Get Trees for Comparison**
   - Use `git rev-parse` to get the tree hash of the merge base.
   - Use `git rev-parse` to get the tree hash of the current slice.
5. **Get Commit Trees in Target Branch**
   Use `git log --format=%T <merge_base>..<into>` to get all tree hashes in the target branch since the merge base.
6. **Compare Trees**
   - For each tree hash in the log, compare it to the slice’s tree hash.
   - If a match is found, the slice is considered merged. Cache and return `true`.
   - If no match is found, cache and return `false`.

### High-Level Overview
```mermaid
graph TD
    A[Start isMerged] --> B{Is result cached?}
    B -- Yes --> C[Return cached result]
    B -- No --> D{Are object IDs equal?}
    D -- Yes --> E[Return false]
    D -- No --> F[Find merge base]
    F --> G[Get tree hash of merge base]
    G --> H[Get tree hash of slice]
    H --> I[Get tree hashes in target branch since merge base]
    I --> J{Any tree hash matches slice tree?}
    J -- Yes --> K[Cache & Return true]
    J -- No --> L[Cache & Return false]
```
### Git Operations Sequence Diagram
```mermaid
sequenceDiagram
    participant Slice
    participant Git
    Slice->>Git: Find merge base (GitMerge.base)
    Slice->>Git: Get merge base tree (git rev-parse <merge_base>^{tree})
    Slice->>Git: Get slice tree (git rev-parse <slice_ref>^{tree})
    Slice->>Git: Get log trees (git log --format=%T <merge_base>..<into>)
    Slice->>Slice: Compare log trees to slice tree
    alt Match found
        Slice->>Slice: Cache & return true
    else No match
        Slice->>Slice: Cache & return false
    end
```
