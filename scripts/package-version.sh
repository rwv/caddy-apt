# Shared by release discovery and package builds.
package_version() {
    local upstream=$1 manifest=$2 revision revision_upstream version
    local label module pinned id source
    {
        read -r revision revision_upstream
        [[ $upstream == "$revision_upstream" ]] || revision=1
        version=${upstream#v}-$revision
        while read -r label module pinned id; do
            source=${module#github.com/}
            source=${source//[\/_-]/.}
            version+="+$source.${pinned//-/.}"
        done
    } < "$manifest"
    printf '%s\n' "$version"
}
