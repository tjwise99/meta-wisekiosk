# Puts the host-resolved sha in do_image[vardeps] so image-buildinfo's
# /etc/buildinfo re-stamps when HEAD moves (#46): the class reads git in
# do_image but hashes nothing, so bitbake would replay a stale stamp.
# Rationale and rejected alternatives: docs/layers-and-kas.md, "What commit an
# image was built from".

include conf/build-rev.inc

# Registered after image.bbclass's own append, which has no separator -- the
# leading space in the literal is what keeps the tokens apart.
python () {
    if not d.getVar('KIOSK_BUILDINFO_REV'):
        bb.fatal("KIOSK_BUILDINFO_REV is unset: run tools/write-build-rev.sh "
                 "before bitbake, or build through `just build` / `just "
                 "kiosk-bundle`, which do it for you. Without it the image "
                 "cannot be kept in step with the commit it was built from.")
    d.appendVarFlag('do_image', 'vardeps', ' KIOSK_BUILDINFO_REV')
}
