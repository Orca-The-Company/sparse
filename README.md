# sparse

`sparse` is a commandline tool that utilises `git` to ease working within stacked pr workflow.
If you wonder what is this stacking pr, please read through the articles available in the net to learn more.

`git` is one of the essential prerequisites. You must have `git` installed and
available in your `path` to make `sparse` work.

## Using sparse

```
sparse check # dumps the status information for the current stack and the PRs
sparse submit # submits the pr for the stack so far or updates the existing PRs for stack
sparse new [<dev> [<target:-main>]] # creates a new stack if no argument provided and there is already a active stack, or creates a new stack if name provided
sparse merge # merges bottom stack if mergeable and there is no block and updates the stack
sparse update # updates the stack `rebase --update-refs`
sparse switch [1..n|<stack_name>] # by default switches the last stack or switches to given stack_name
```
