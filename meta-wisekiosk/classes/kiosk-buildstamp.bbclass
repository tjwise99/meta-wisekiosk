# Bake this repository's commit into every image, at ${sysconfdir}/build-info
# (#46 image build stamp). Mechanism and rationale: docs/layers-and-kas.md.
#
# Not recorded: build timestamp, hostname, username -- reproducibility, and
# guard 6 keeps identifying detail out of a public repository.

def kiosk_layerdir(d):
    """This layer's path, from BBLAYERS.

    Not COREBASE: oe.buildcfg.get_scmbasepath joins COREBASE with 'meta', which
    is why METADATA_REVISION reports poky's HEAD -- a kas pin already recorded in
    includes/base.yaml, and never this repository's commit.
    """
    for layer in (d.getVar('BBLAYERS') or '').split():
        path = os.path.normpath(layer)
        if os.path.basename(path) == 'meta-wisekiosk':
            return path
    return ''

def kiosk_git(d, cmd, cwd=None):
    """Run git in the layer, or in cwd. None on any failure.

    None rather than '' because the two must not collide: `git status
    --porcelain` prints nothing on a clean tree, so a failed run that returned ''
    would report a dirty tree as clean.
    """
    import bb.process
    path = cwd or kiosk_layerdir(d)
    if not path:
        return None
    try:
        out, _ = bb.process.run(cmd, cwd=path,
                                env=dict(os.environ, PSEUDO_UNLOAD='1'))
    except bb.process.CmdError:
        return None
    return out.strip()

def kiosk_commit(d):
    """The full sha of the repository this layer belongs to, or <unknown>.

    <unknown>, not '', so the file records that the build could not attribute
    itself; tools/build-stamp-check.sh's 40-hex assertion turns that into a
    failure rather than a quiet wrong answer.

    git walks upward from the layer, so the answer is the PARENT repository's
    HEAD -- correct here, where bblayers.conf resolves the layer to a
    subdirectory of the bind-mounted repository root, and silently about the
    wrong repository if this layer were ever vendored into a different parent.
    kiosk-zero-w.yaml is that repository's marker.
    """
    top = kiosk_git(d, 'git rev-parse --show-toplevel')
    if not top:
        return '<unknown>'
    if not os.path.exists(os.path.join(top, 'kiosk-zero-w.yaml')):
        bb.warn('kiosk-buildstamp: %s answers for %s but carries no '
                'kiosk-zero-w.yaml -- META_WISEKIOSK_COMMIT names a different '
                'repository than the one this layer was written for'
                % (top, kiosk_layerdir(d)))
    return kiosk_git(d, 'git rev-parse HEAD') or '<unknown>'

def kiosk_dirty(d):
    """1 if the working tree differs from the commit above, tracked or untracked.

    Repository-scoped, matching META_WISEKIOSK_COMMIT: kiosk-zero-w.yaml,
    includes/ and patches/ are build inputs living outside the layer. git status,
    not oe.buildcfg.is_layer_modified, which is `git diff` only and reads a new
    untracked .bb as clean while BBFILES puts it in the image. An unreadable tree
    counts as dirty. Dirty is reported, never refused (owner, 2026-08-18).
    """
    top = kiosk_git(d, 'git rev-parse --show-toplevel')
    if not top:
        return '1'
    status = kiosk_git(d, 'git status --porcelain', cwd=top)
    return '0' if status == '' else '1'

def kiosk_build_layers(d):
    """Every layer as name:shortsha, flattened onto one line.

    Informational -- the guard asserts META_WISEKIOSK_COMMIT only. It narrows,
    and does not close, the gap that sources/ is gitignored.

    get_layer_revisions' modified flag is dropped: it is `git diff` only and
    would contradict META_WISEKIOSK_DIRTY. `path` is dropped as the builder's
    absolute path, and this file ships in a public image.
    """
    tokens = []
    for _path, name, _branch, rev, _modified in oe.buildcfg.get_layer_revisions(d):
        tokens.append('%s:%s' % (name, rev[:12]))
    return ' '.join(tokens)

# := + [vardepvalue] (as metadata_scm.bbclass): hash the value, not the
# expression.
WISEKIOSK_COMMIT := "${@kiosk_commit(d)}"
WISEKIOSK_COMMIT[vardepvalue] = "${WISEKIOSK_COMMIT}"
# Sliced from the captured value rather than asked of git again, so the short sha
# cannot disagree with the long one. 12, not 7: the field is meant to be quoted
# in an investigation write-up years after the tree outgrew 7.
WISEKIOSK_COMMIT_SHORT := "${@d.getVar('WISEKIOSK_COMMIT')[:12]}"
WISEKIOSK_COMMIT_SHORT[vardepvalue] = "${WISEKIOSK_COMMIT_SHORT}"
WISEKIOSK_DIRTY := "${@kiosk_dirty(d)}"
WISEKIOSK_DIRTY[vardepvalue] = "${WISEKIOSK_DIRTY}"
# On a detached checkout git answers the literal `HEAD`, recorded as-is.
WISEKIOSK_BRANCH := "${@kiosk_git(d, 'git rev-parse --abbrev-ref HEAD') or '<unknown>'}"
WISEKIOSK_BRANCH[vardepvalue] = "${WISEKIOSK_BRANCH}"
WISEKIOSK_BUILD_LAYERS := "${@kiosk_build_layers(d)}"
WISEKIOSK_BUILD_LAYERS[vardepvalue] = "${WISEKIOSK_BUILD_LAYERS}"

# Shell-sourceable KEY=VALUE; every value quoted (see docs/layers-and-kas.md).
#
# ROOTFS_POSTPROCESS_COMMAND, not IMAGE_PREPROCESS_COMMAND: this runs before
# reproducible_final_image_task, so the new file's mtime gets the same clamp as
# the rest of the rootfs.
#
# The heredoc delimiter is quoted -- bitbake expands ${...} in the function body
# before the shell ever sees it, so quoting only stops bash re-expanding a value.
kiosk_write_build_info() {
    cat > ${IMAGE_ROOTFS}${sysconfdir}/build-info <<'EOF'
BUILD_INFO_VERSION="1"
META_WISEKIOSK_COMMIT="${WISEKIOSK_COMMIT}"
META_WISEKIOSK_COMMIT_SHORT="${WISEKIOSK_COMMIT_SHORT}"
META_WISEKIOSK_DIRTY="${WISEKIOSK_DIRTY}"
META_WISEKIOSK_BRANCH="${WISEKIOSK_BRANCH}"
BUILD_MACHINE="${MACHINE}"
BUILD_DISTRO="${DISTRO}"
BUILD_DISTRO_VERSION="${DISTRO_VERSION}"
BUILD_LAYERS="${WISEKIOSK_BUILD_LAYERS}"
EOF
    chmod 0644 ${IMAGE_ROOTFS}${sysconfdir}/build-info
}

# Bare name, no trailing ';': a glued ';' is not a resolvable variable name, so
# the body reaches no task hash. Enforced by guard 9 in tools/ci-guards.sh;
# mechanism in docs/layers-and-kas.md.
ROOTFS_POSTPROCESS_COMMAND += "kiosk_write_build_info"
