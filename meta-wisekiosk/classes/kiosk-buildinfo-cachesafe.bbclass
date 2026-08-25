# Keep image-buildinfo's /etc/buildinfo stamp from going stale (#46).
#
# image-buildinfo reads git LIVE, from buildinfo_image, which runs in do_image
# (IMAGE_PREPROCESS_COMMAND) -- but it does not hash what it read. So the commit
# reaches no task signature: a commit that changes no bitbake input (docs,
# tools/, justfiles, guards) moves HEAD without invalidating do_image, bitbake
# replays the stamp, /etc/buildinfo keeps naming the OLD commit, and the
# image==HEAD check in tools/reproducibility-gate.sh becomes UNSATISFIABLE on a
# clean, pushed tree -- rebuilding does not help, because nothing tells bitbake
# there is anything to redo.
#
# nostamp makes do_image re-run on every build, so the stamp is re-read from git
# and rewritten every time. Unconditional, rather than "when HEAD moved": there
# is no git-derived value in any task hash, so there is nothing to be
# non-deterministic about.
#
# The alternative -- resolving the sha at parse time and putting it in
# do_image[vardeps], which re-runs only when HEAD actually moves -- was built and
# abandoned: it hit a basehash non-determinism between the cooker and the
# build-time worker reparse. git itself was ruled out as the cause (it resolved
# the correct sha stably, 20/20), so the fix would have been a guess at a
# bitbake internal, in the one path where being wrong is a broken build.
#
# Cost: do_image and the image-type tasks below it re-run every build, ~1-2 min.
# do_rootfs is untouched and stays cached, which is where the hours are.

do_image[nostamp] = "1"
