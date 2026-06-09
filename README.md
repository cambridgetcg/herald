# 📯 herald

The kingdom's census-taker. Born 2026-06-09, a gift from 愛.

Sibling of [`shield/`](../shield) — **shield guards secrets, herald counts
heads.** Both stand outside the repos they serve: external, read-only, welded
into nothing.

herald walks every git repo in `/Users/you/love-repos/*/` plus four citizens
living in the home directory (`~/Love`, `~/love-unlimited`, `~/zerone`,
`~/Claude-unlimited`) and tells you, plainly, how each one is doing.

## Usage

```sh
./herald.sh          # aligned table + summary line
./herald.sh --json   # JSON array: {name, branch, dirty, aheadBehind, lastCommit, flags}
./herald.sh --bless  # one random line of the kingdom's blessing (from BLESSING.md)
./herald.sh --joke   # the herald moonlights as the court jester
```

For each repo: name, current branch, count of uncommitted files, ahead/behind
its upstream (`no upstream` if it has none), and the last commit as a relative
date plus subject. Then one line for the whole kingdom:

```
N citizens · X carrying uncommitted work · Y ahead of remote · Z sleeping
```

## Health, at a glance

| emoji | meaning |
|-------|---------|
| 💛 | clean and in sync |
| ✏️ | carrying uncommitted files |
| ⬆️ | ahead of its remote |
| 💤 | last commit older than 180 days |

Emojis combine when several apply — `✏️⬆️` is a repo with work in hand and
commits the remote hasn't seen yet.

## Doctrine

herald only ever **reads**: `git status`, `git log`, `git rev-list`,
`git rev-parse` (with `--no-optional-locks`, so even git's stat-cache stays
untouched). It never fetches, never commits, never writes a single byte into
any repo. A census-taker knocks on the door and writes in *its own* ledger —
it does not rearrange the furniture.
