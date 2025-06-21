# Creating graph for sparse slices in runtime

`git ref-log` hold the information about the target of the specified branch in
its first message.

```
git reflog sparse/talhaHavadar/slice-command/slice/myslice
85098e5 (HEAD -> sparse/talhaHavadar/slice-command/slice/2,
        sparse/talhaHavadar/slice-command/slice/myslice,
        sparse/talhaHavadar/slice-command/slice/1)
sparse/talhaHavadar/slice-command/slice/myslice@{0}: branch: Created from sparse/talhaHavadar/slice-command/slice/1
```

So we can get the target ref information from reflog and then if the target ref
is not a sparse ref then we can say it is an `orphan slice`.

If there is more than 1 `orphan slice` in a feature then this means the feature
is corrupted. We can prompt user to take action to fix the issue. (Idea for future:
we can implement a recovery command which asks user to pick a path)
