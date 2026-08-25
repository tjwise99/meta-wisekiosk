# Make image-buildinfo's /etc/buildinfo stamp cache-safe (#46).
#
# image-buildinfo reads git LIVE, from buildinfo_image, which runs in do_image
# (IMAGE_PREPROCESS_COMMAND, image.bbclass) -- so the commit it writes reaches no
# task signature. A commit that changes no bitbake input (docs, tools/,
# justfiles, guards) moves HEAD without invalidating do_image: bitbake replays
# the stamp, /etc/buildinfo keeps naming the OLD commit, and the image==HEAD
# check in tools/reproducibility-gate.sh becomes UNSATISFIABLE on a clean,
# pushed tree -- rebuilding does not help, because nothing tells bitbake to.
#
# Tying the sha VALUE into do_image's vardeps makes that task re-run exactly when
# HEAD moves, and not otherwise. Deliberately NOT do_image[nostamp], which would
# re-run on every build even when HEAD is unchanged.
#
# do_image, not do_rootfs: do_rootfs never reads IMAGE_PREPROCESS_COMMAND, so
# hooking it there would force the expensive rootfs re-assembly to fix a file
# written a task later. do_image_ext4 and do_image_complete are downstream, so
# the deployed .ext4 the gate reads is regenerated; IMAGE_ROOTFS survives a
# stamped do_rootfs, whose cleandirs apply only when it actually runs. Upstream
# appends to this same flag in image.bbclass.
#
# The sha is resolved with the SAME oe.buildcfg helper image-buildinfo itself
# calls, over the same BBLAYERS-by-basename path, so the value hashed here is
# byte-identical to the one written. Two independent resolvers could disagree,
# and then do_image would re-run keyed on one sha while the file recorded
# another -- a gate that refuses forever with no way out.
#
# Only the sha is hashed, matching what the gate compares. A branch rename that
# leaves the sha alone therefore does not re-stamp, and /etc/buildinfo keeps the
# old branch name until something else re-runs do_image. Cosmetic: nothing reads
# that field.

def kiosk_buildinfo_rev(d):
    import os
    import oe.buildcfg

    for path in (d.getVar('BBLAYERS') or '').split():
        if os.path.basename(os.path.normpath(path)) != 'meta-wisekiosk':
            continue
        rev = oe.buildcfg.get_metadata_git_revision(path)
        # oe.buildcfg swallows git failure and returns the literal <unknown>.
        # Fail here rather than let it through: as a vardep that value is
        # CONSTANT, so do_image would stop re-running and cache safety would be
        # silently dead behind an image that still looks valid -- while
        # execution, running later and possibly succeeding, wrote a real sha.
        if not rev or rev == '<unknown>':
            bb.fatal("kiosk-buildinfo-cachesafe: cannot read the meta-wisekiosk "
                     "git revision at %s. A build that cannot name its own "
                     "commit must not produce an image." % path)
        return rev
    bb.fatal("kiosk-buildinfo-cachesafe: no meta-wisekiosk layer in BBLAYERS -- "
             "the layer was renamed or dropped, and nothing would record the "
             "commit this image was built from.")

KIOSK_BUILDINFO_REV := "${@kiosk_buildinfo_rev(d)}"
KIOSK_BUILDINFO_REV[vardepvalue] = "${KIOSK_BUILDINFO_REV}"

do_image[vardeps] += "KIOSK_BUILDINFO_REV"
