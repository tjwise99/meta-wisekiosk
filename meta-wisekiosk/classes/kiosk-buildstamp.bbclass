# Bake this repository's commit into every image, at ${sysconfdir}/build-info.
#
# The three files that look like provenance are not: DISTRO_VERSION is the
# hardcoded "0.1" upstream sets, /etc/os-release derives from it, and
# /etc/version is the reproducible-build epoch clamp -- identical on every build
# of every project. An image built today and one built in June are byte-identical
# in all three, so a running slot cannot name the source it came from and an
# investigation cannot attribute what it measured (issue #46).
#
# Why a postprocess and not a recipe: a package recipe running `git` inside
# do_install produces a task hash bitbake cannot invalidate, sstate replays the
# old .ipk, and every later image bakes the sha of whichever commit happened to
# be checked out first -- a file that exists, parses, and is WRONG. The image
# path cannot do that: rootfs_variables() (image.bbclass) puts
# ROOTFS_POSTPROCESS_COMMAND in do_rootfs[vardeps], bitbake resolves each name in
# it to a function and hashes that function's body and variable references, so
# the values below reach the task hash -- see the separator note above
# ROOTFS_POSTPROCESS_COMMAND, which is what makes that resolution happen. Image
# tasks also carry SSTATE_SKIP_CREATION, so there is no cached artifact to replay
# over a changed hash.
#
# The capture is in configuration space with := and a [vardepvalue], copying
# metadata_scm.bbclass: without that flag bitbake hashes the expression text
# rather than its value, and the sha would never move the hash.
#
# NOT recorded: build timestamp, builder hostname, builder username. The latter
# two are the identifying detail guard 6 exists to keep out of a public
# repository, arriving by a route no guard watches.
#
# The reproducibility unit is therefore commit + branch + dirty state, not commit
# alone: BRANCH and DIRTY are baked and hashed, and neither is a function of the
# commit. The same tree built on two branches, or built dirty and then clean,
# yields different files and re-runs do_rootfs. Excluding a timestamp is what
# keeps the unit that small -- a timestamp would make even a repeat build of one
# commit on one branch differ. On a detached checkout `git rev-parse
# --abbrev-ref HEAD` answers the literal `HEAD`, which is recorded as-is.

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

    <unknown>, not '', so the shipped file records that the build could not
    attribute itself; tools/build-stamp-check.sh's 40-hex assertion is what turns
    that into a red flash rather than a quiet wrong answer. Inside kas-container
    the likely cause is git refusing the bind-mounted tree as dubiously owned.

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

    Scoped to the whole repository, matching META_WISEKIOSK_COMMIT, which is the
    repository's HEAD and not the layer's (owner, 2026-08-18). kiosk-zero-w.yaml,
    includes/ and patches/ are build inputs living outside the layer, so a
    layer-scoped flag would read 0 while an uncommitted edit to any of them moved
    the image.

    git status, not oe.buildcfg.is_layer_modified, which is `git diff` only: a
    brand-new untracked .bb reads clean there, and BBFILES in conf/layer.conf
    picks that file up, so it IS in the image. The cost is that a stray editor
    swapfile flips the flag, which is the intended trade.

    Recorded, never refused. A build that will not run on a dirty tree makes the
    develop loop hostile; making the fact legible is the whole job, and an
    investigation quoting META_WISEKIOSK_DIRTY=1 is already disqualified by its
    own standard. An unreadable tree counts as dirty.
    """
    top = kiosk_git(d, 'git rev-parse --show-toplevel')
    if not top:
        return '1'
    status = kiosk_git(d, 'git status --porcelain', cwd=top)
    return '0' if status == '' else '1'

def kiosk_build_layers(d):
    """Every layer as name:shortsha, flattened onto one line.

    Informational -- the guard asserts META_WISEKIOSK_COMMIT only. It narrows,
    and does not close, the gap that sources/ is gitignored: a hand-patched
    upstream layer or a rotated signing key moves the image without moving this
    repository's HEAD.

    get_layer_revisions also offers a modified flag; it is dropped rather than
    emitted. It is `git diff` (tracked only), so it would print a bare
    meta-wisekiosk token -- read as "clean" -- for a tree META_WISEKIOSK_DIRTY
    calls dirty. One file must not answer the same question two ways, and DIRTY
    is the answer meant to be quoted. `path` is likewise discarded: it is the
    builder's absolute path, and this file ships in a public image.
    """
    tokens = []
    for _path, name, _branch, rev, _modified in oe.buildcfg.get_layer_revisions(d):
        tokens.append('%s:%s' % (name, rev[:12]))
    return ' '.join(tokens)

WISEKIOSK_COMMIT := "${@kiosk_commit(d)}"
WISEKIOSK_COMMIT[vardepvalue] = "${WISEKIOSK_COMMIT}"
# Sliced from the captured value rather than asked of git again, so the short sha
# cannot disagree with the long one. 12, not 7: the field is meant to be quoted
# in an investigation write-up years after the tree outgrew 7.
WISEKIOSK_COMMIT_SHORT := "${@d.getVar('WISEKIOSK_COMMIT')[:12]}"
WISEKIOSK_COMMIT_SHORT[vardepvalue] = "${WISEKIOSK_COMMIT_SHORT}"
WISEKIOSK_DIRTY := "${@kiosk_dirty(d)}"
WISEKIOSK_DIRTY[vardepvalue] = "${WISEKIOSK_DIRTY}"
WISEKIOSK_BRANCH := "${@kiosk_git(d, 'git rev-parse --abbrev-ref HEAD') or '<unknown>'}"
WISEKIOSK_BRANCH[vardepvalue] = "${WISEKIOSK_BRANCH}"
WISEKIOSK_BUILD_LAYERS := "${@kiosk_build_layers(d)}"
WISEKIOSK_BUILD_LAYERS[vardepvalue] = "${WISEKIOSK_BUILD_LAYERS}"

# Shell-sourceable KEY=VALUE, one fact per line. BUILD_INFO_VERSION so a later
# format change is a detectable failure in tools/build-stamp-check.sh rather than
# a silent parse difference.
#
# ROOTFS_POSTPROCESS_COMMAND, not IMAGE_PREPROCESS_COMMAND: this runs before
# reproducible_final_image_task, so the new file's mtime gets the same clamp as
# the rest of the rootfs.
#
# The heredoc delimiter is quoted -- bitbake expands ${...} in the function body
# before the shell ever sees it, so quoting only stops bash re-expanding a value.
#
# EVERY value is quoted, including the ones that cannot contain a space. The
# designed failure value is the literal <unknown>, and < > are redirection
# operators: unquoted, `. /etc/build-info` dies with a syntax error, leaves the
# field EMPTY rather than <unknown>, and abandons every later line in the file.
# The one path built to be loud would read as "field absent". Quoting is what
# keeps the shell-sourceable contract true on the failure path, which is the only
# path where it matters. tools/build-stamp-check.sh strips the quotes in awk.
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

# No trailing semicolon, and this is load-bearing rather than style. The two
# consumers of this variable disagree about the separator: oe.utils
# execute_pre_post_process does cmds.replace(";", " ") before splitting, so
# "kiosk_write_build_info;" RUNS; bitbake's dependency scanner does not, and
# records the token verbatim as a name. "kiosk_write_build_info;" resolves to no
# variable, so its body -- and every WISEKIOSK_* reference in it -- contributes
# nothing to do_rootfs's hash. The stamp would then be written on the first build
# and never again: the file exists, parses, and silently names whichever commit
# was checked out when do_rootfs last ran, which is the exact stale-sha defect
# issue #46 exists to prevent. Bare, the name resolves and WISEKIOSK_COMMIT lands
# in do_rootfs's dependency list, which is what makes the sha bust the hash.
#
# The trap is class-wide, not specific to this class: any postprocess function
# appended with a semicolon has an unhashed body, so editing what it does leaves
# do_rootfs stamped and the previous output shipped. Guard 9 in tools/ci-guards.sh
# rejects the form across every class here, because a comment saying "do not do
# this" is a finding and not a mitigation.
ROOTFS_POSTPROCESS_COMMAND += "kiosk_write_build_info"
