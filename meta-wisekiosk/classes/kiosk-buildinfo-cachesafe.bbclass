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

# do_image[vardeps] is appended to by image.bbclass's own anonymous python:
#
#     d.appendVarFlag('do_image', 'vardeps', ' '.join(vardeps))          # :433
#
# with NO leading separator -- unlike the sibling call for the per-type tasks,
# which passes ' ' + ' '.join(...). So whatever token is LAST in that flag is
# welded to the first token appended there. A plain
# `do_image[vardeps] += "KIOSK_BUILDINFO_REV"` therefore produced the phantom
# KIOSK_BUILDINFO_REVIMAGE_TYPEDEP:wic.bz2 -- empty, no dependencies, CONSTANT --
# so do_image's hash never moved and the mechanism was inert while reading as
# correct. Same separator trap as the trailing `;` this branch opened with.
#
# Worse, the welded partner is NON-DETERMINISTIC: that list is built from a
# Python set (image.bbclass :370), whose iteration order varies between
# processes, so the phantom's NAME differs between the cooker and a worker. A
# varying dependency name is a varying basehash -- almost certainly what the
# earlier parse-time-git attempt was really hitting.
#
# The separation is therefore ORDER-BASED, not whitespace-based. This class is
# inherited through IMAGE_CLASSES, which image.bbclass pulls in via
# `inherit_defer ${IMGCLASSES}` (:25). bitbake applies deferred inherits inside
# finalize() BEFORE running anonymous functions (parse/ast.py :394-400), and
# runAnonFuncs executes __BBANONFUNCS in registration order -- so a deferred
# class's anonymous python is registered last and RUNS AFTER :433. Appending
# there means nothing is concatenated onto our token afterwards.
#
# The leading space is belt-and-braces for the token before ours. It sits at the
# START of a Python string literal, so no trailing-whitespace stripper, editor
# or formatter can silently eat it -- which a bare trailing space in a bitbake
# assignment could.
#
# Nothing static can prove the seam held: a guard reads source text, and only a
# parsed signature shows the truth. The backstop is the reproducibility gate --
# if this goes inert the deployed image goes stale and the gate REFUSES at
# flash. Loud, never silent. Acceptance is `bitbake-dumpsig` on do_image listing
# KIOSK_BUILDINFO_REV as its OWN entry, value == the host sha.
python () {
    if not d.getVar('KIOSK_BUILDINFO_REV'):
        bb.fatal("KIOSK_BUILDINFO_REV is unset: run tools/write-build-rev.sh "
                 "before bitbake, or build through `just build` / `just "
                 "kiosk-bundle`, which do it for you. Without it the image "
                 "cannot be kept in step with the commit it was built from.")
    d.appendVarFlag('do_image', 'vardeps', ' KIOSK_BUILDINFO_REV')
}
