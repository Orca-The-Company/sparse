# `sparse update` command

We have challenges with PRs merged with merge commit and squash. Squash commits completely invalidates the
history in a `slice` and creates 1 commit that combines all the commits. So git doesnt really know how to
create relations between a `slice` and a squashed commit that has all commits in a `slice`. It thinks that
they are different things.

Options to overcome this limitation:
- We can check all the slices in the feature and check the diff of them with the target branch, after every merge.
  - if we dont see any diff for one of the slices in the feature then that means that slice is the one recently merged.
  - Things to consider here: all of the slices may have been merged already for the feature and there might be additional
  changes in the target branch, which will lead to a diff result for all slices. Similarly if none of the slices has been
  merged recently this will also cause the same result.

If user uses `rebase` to merge PRs then it is a lot easier to track down what is merged or not. Switching to last slice
and running `git rebase <target> --update-refs` updates the slices in between as well and then each slice can be pushed
to its corresponding remote (maybe with `git config branch.<branch-name>.remote` if there is no remote no need to update?).

## Comparing tree diffs to determine if a slice is merged
- Make sure to fetch all latest update for the target branch
  - `git fetch origin main` or we can fetch all
- Find the leaf slice for the feature (using slice graph)
- Find the commit that leaf slice is originated from `git merge-base origin/main <slice>`, lets call this `BASE_COMMIT` from now on
- Constructing signature for the slice to compare later
  - `git merge-base origin/main sparse/talhaHavadar/bbb/slice/1`    >> to find merge base
  - `git rev-parse 0936548e565e8cb2f418a61f976a0d46344a51eb^{tree}` >> to find tree for the base
  - `git rev-parse sparse/talhaHavadar/bbb/slice/1^{tree}` >> tree for base
  -
  ```
  git log --format=%T origin/main
  ecad67691852882849effb28faeba3f2d28dd7aa
  0c2c47cd29d1e6542aad626705269ba1dfbb5e77
  a59382a78c21daa47d0f5b035306858aca252eae
  ```
  - `git merge-base --is-ancestor $SLICE_TIP origin/main` >> check if it is merged with merge commit

## Algorithm to update
- Initialization:
  - `git fetch --all --prune` get the absolute latest state from all remotes (maybe omit prune?).
  - We already have slices graph for the active feature. So we can use this graph to loop through slices in feature.
  - Identify the target branch (e.g., main). This can be done by checking the target(recursively until null then ref.createdFrom) of leafNode in slice graph.
- Merge Detection Loop:
    - Iterate through your slices from bottom to top (slice-1 to slice-N).
    - For each slice-k:
      - First, check the easy way: has it been merged by rebase/merge-commit? The commits of a merged branch will be part of the target branch's history.
        - we can get the tip of a slice like (`slice.ref` << this points the tip of the slice)
        - Check if that commit is an ancestor of the target branch `git merge-base --is-ancestor $SLICE_TIP origin/main` If this succeeds, the slice (and all below it) are merged.
        - Mark them as such and continue to the next slice.
      - If not, check for a squash merge using the "Comparing Tree Diffs" algorithm described in [Comparing tree diffs](#comparing-tree-diffs-to-determine-if-a-slice-is-merged).
        - If a squash merge is detected, mark the slice as merged and "re-parent" (`git rebase --onto <new-parent> <old-parent> <branch-to-move>`) the next slice (slice-k+1) to be based on the new origin/main.
        - If no merge is detected, stop the loop. slice-k is the first unmerged slice.
- Rebase Remaining Slices:
  - Once we found the first unmerged slice (slice-k), we know that it and all slices above it (slice-k+1 to slice-N) need to be updated.
  - Perform the `git rebase --update-refs` routine on the entire remaining stack (slice-k through slice-N).
    - `git rebase origin/main --onto origin/main $STACK_BASE $STACK_TIP --update-refs`
    - `git merge-base origin/main <last-slice-in-stack>` << can be useful to find the commit that entire feature began.
