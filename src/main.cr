require "./github"

# If this programme's name begins with "git-", it will use a section of the
# git configuration which matches the rest of the name. For example, if it's
# run as "git-xyz", it will look for values in the "xyz" section. It defaults
# to behaving as though it's called "git-hub".
prog = Path[PROGRAM_NAME].basename
github = GitHub.git(/^git-(.+)$/.match(prog).try(&.[1]) || "hub")

exit github.run(ARGV)
