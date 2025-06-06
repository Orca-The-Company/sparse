# sparse

`sparse` is a commandline tool that utilises `git` to ease working within stacked pr workflow.
If you wonder what is this stacking pr, please read through the articles available in the net to learn more.

`git` is one of the essential prerequisites. You must have `git` installed and
available in your `path` to make `sparse` work.

## Using sparse

```
sparse check
sparse feature --help
sparse slice --help
sparse submit # submits the pr for the stack so far or updates the existing PRs for stack
sparse config # alias for git config/stackpr settings for the repo
```

## Interactions with git

Sparse uses git to handle all git related operations so `git` must be present
in `PATH`. Please follow the instructions on [git-scm](https://git-scm.com/) to
install it.

### Stacking with git branches

Sparse creates a new branch for every stack in a feature. In stack layout below
`create-fancy-button` branch is the main feature branch that we are currently working on.
The stacks we are building, we call them `slices`, are created using nested branching
strategy.

```
sparse/create-fancy-button                                          ==> feature
`-- sparse/<config.email>/create-fancy-button/(n|<slice>)           ==> stack
    `-- sparse/<config.email>/create-fancy-button/(n+1|<slice>)     ==> stack
        `-- sparse/<config.email>/create-fancy-button/(n+2|<slice>) ==> stack
```

You can give a name for your each `slice` under main `feature` to point them easily
when you need to refactor them. You can of course skip naming your slices, in that
case they will have an incrementing number as a name.

#### New feature development workflow

To start a new feature, developer must use `sparse feature` command,
see details of the command below:

```
sparse feature [ options ] <feature_name> [<slice_name>]
    args:
        <feature_name>: name of the feature to be created. If a feature with the
                        same name exists, sparse simply switches to that feature.
        <slice_name>:   name of the first slice in newly created feature. This
                        argument is ignored if the feature already exists.
    options:
        --help: Shows this help message
        --to <base_(feature/branch)>: branch or feature to build on top (default: main)
```

Then do your work as usual using `git`. And you feel like you make enough changes for a single PR, then
use `sparse submit` command to submit your changes to remote and create PRs for your slices.
To continue working on the feature with a new slice use `sparse slice` command to create
new slice.

```
sparse slice [ options ] [ <slice_name> ]
    args:
        <slice_name>:   name of the new slice in the feature. If the slice with
                        the same name exists, then sparse switches to that slice
                        If the slice name is not provided, then sparse creates
                        the slice based on the number of slices currently in the feature.
    options:
        --help:   Shows this help message
        --before: Creates new slice before (current or given) slice
        --after:  Creates new slice after (current or given) slice

```

Say you got some feedback for your old slices, save what you were doing via `git stash` or
commit temporarily as usual with `git commit`. Then switch to slice that you want to update
with `sparse slice <slice_you_want_to_update>`, do your magic, commit your changes then
submit as usual with `sparse submit` command.

```
sparse submit [ options ]
    Creates PRs for slices in the feature
    options:
        -d, --draft: creates PRs as drafts if it is supported.
```
