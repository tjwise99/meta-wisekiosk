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
# Putting the sha in do_image's vardeps fixes that by HASH: a new sha means a new
# do_image signature, no matching sstate entry, and therefore do_image,
# do_image_ext4 and do_image_complete all regenerate. Correct by construction,
# and safe under an sstate mirror -- where do_image[nostamp] would not be, since
# nostamp forces re-execution without changing a hash, leaving setscene free to
# restore a stale, unchanged-hash do_image_complete.
#
# The sha is resolved on the HOST by tools/write-build-rev.sh and read here as a
# plain assignment. Nothing is computed at parse time: no python, no git, no
# subprocess, no environment -- so every parse in every context, cooker and
# build-time worker alike, reads the same bytes. Resolving it inside bitbake was
# tried and abandoned; a parse-time `${@git...}` produced a basehash that
# differed between the cooker and the worker reparse.
#
# The host is also the right authority. The gate compares the image against the
# HOST's HEAD, so that is the value whose movement must force a re-stamp. What
# gets WRITTEN into the file stays image-buildinfo's own live in-container read,
# and whether it is correct is the gate's business, not this one's -- the two
# concerns are deliberately not coupled.

# include, not require: absence is reported below with something an operator can
# act on, rather than bitbake's generic missing-file error.
include conf/build-rev.inc

KIOSK_BUILDINFO_REV[vardepvalue] = "${KIOSK_BUILDINFO_REV}"

do_image[vardeps] += "KIOSK_BUILDINFO_REV"

python () {
    if not d.getVar('KIOSK_BUILDINFO_REV'):
        bb.fatal("KIOSK_BUILDINFO_REV is unset: run tools/write-build-rev.sh "
                 "before bitbake, or build through `just build` / `just "
                 "kiosk-bundle`, which do it for you. Without it the image "
                 "cannot be kept in step with the commit it was built from.")
}
