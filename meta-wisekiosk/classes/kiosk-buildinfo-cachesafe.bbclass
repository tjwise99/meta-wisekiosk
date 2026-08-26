# Keep image-buildinfo's /etc/buildinfo stamp from going stale (#46).
#
# image-buildinfo reads git live in do_image (buildinfo_image, an
# IMAGE_PREPROCESS_COMMAND) but does not hash what it read, so the sha reaches
# no task signature: a commit that changes no bitbake input moves HEAD, bitbake
# replays the stamp, and the image==HEAD check in tools/reproducibility-gate.sh
# cannot be satisfied on a clean, pushed tree.
# Putting the host-resolved sha in do_image[vardeps] fixes that by HASH:
# do_image, do_image_ext4 and do_image_complete regenerate, do_rootfs stays
# cached. The sha comes from tools/write-build-rev.sh as a plain assignment --
# nothing is computed at parse time, so every context reads the same bytes.
#
# Two mechanisms tried and abandoned: a parse-time `${@git...}` (basehash
# differed between the cooker and the worker reparse) and do_image[nostamp]
# (re-executes without changing a hash, so setscene can still restore a stale
# do_image_complete).
#
# Operator-facing behaviour: docs/layers-and-kas.md, "What commit an image was
# built from".

# include, not require: the bb.fatal below is the operator-facing message.
include conf/build-rev.inc

# Appended after image.bbclass:433, which appends to this flag with no leading
# separator -- a token left last there is welded onto the next one and becomes a
# phantom, empty, constant variable. The separation is ORDER-based: IMAGE_CLASSES
# is a deferred inherit, so this anonymous python is registered last and runs
# after :433. The leading space sits inside the string literal, where no
# whitespace stripper can eat it. No static check can prove the seam held; the
# backstop is the gate refusing a stale image at flash.
python () {
    if not d.getVar('KIOSK_BUILDINFO_REV'):
        bb.fatal("KIOSK_BUILDINFO_REV is unset: run tools/write-build-rev.sh "
                 "before bitbake, or build through `just build` / `just "
                 "kiosk-bundle`, which do it for you. Without it the image "
                 "cannot be kept in step with the commit it was built from.")
    d.appendVarFlag('do_image', 'vardeps', ' KIOSK_BUILDINFO_REV')
}
