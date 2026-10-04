#!/bin/bash
# Append-only, data-only journal. A tombstone supersedes an earlier record.

state_validate() {
    local file=$STATE_DIR/journal.tsv
    [ ! -L "$STATE_DIR" ] && [ ! -L "$file" ] || {
        fail 'Refusing a symlinked ownership journal.'; return 1;
    }
    [ -e "$file" ] || return 0
    [ -f "$file" ] || { fail 'Ownership journal is not a regular file.'; return 1; }
    awk -F '\t' 'NR == 1 { if ($0 != "dotfiles-state\t1") exit 1; next }
        NF != 4 { exit 1 }
        END { if (NR == 0) exit 1 }' "$file" || {
        fail 'Unsupported or damaged ownership journal; preserve it and investigate.'; return 1;
    }
}

state_initialize_file() {
    (umask 077; mkdir -p "$STATE_DIR" && printf 'dotfiles-state\t1\n' > "$STATE_DIR/journal.tsv")
}

state_init() {
    state_validate || return $?
    [ ! -f "$STATE_DIR/journal.tsv" ] || return 0
    run state_initialize_file
}

state_append() {
    (umask 077; printf '%s\t%s\t%s\t%s\n' "$@" >> "$STATE_DIR/journal.tsv")
}

state_record() {
    local field
    [ "$#" = 4 ] || { fail 'Invalid state record.'; return 1; }
    [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] || {
        fail 'State kind, key and value must be nonempty.'; return 1;
    }
    for field in "$@"; do
        case "$field" in
            *$'\t'*|*$'\n'*|*$'\r'*) fail 'State fields must be single-line data without tabs.'; return 1 ;;
        esac
    done
    if [ "$DRY_RUN" = 1 ]; then
        return 0
    fi
    state_init || return $?
    run state_append "$@"
}

state_field() {
    [ -f "$STATE_DIR/journal.tsv" ] || return 0
    state_validate || return $?
    DOTFILES_STATE_KIND=$1 DOTFILES_STATE_KEY=$2 awk -F '\t' -v field="$3" '
        BEGIN { kind = ENVIRON["DOTFILES_STATE_KIND"]; key = ENVIRON["DOTFILES_STATE_KEY"] }
        NR > 1 && $1 == kind && $2 == key { value = $field; deleted = ($3 == "@deleted") }
        END { if (!deleted && value != "") print value }
    ' "$STATE_DIR/journal.tsv"
}

state_value() { state_field "$1" "$2" 3; }
state_extra() { state_field "$1" "$2" 4; }

state_each() {
    [ -f "$STATE_DIR/journal.tsv" ] || return 0
    state_validate || return $?
    awk -F '\t' -v kind="$1" '
        NR > 1 && $1 == kind {
            if (!($2 in records)) keys[++count] = $2
            records[$2] = $3 "\t" $4; deleted[$2] = ($3 == "@deleted")
        }
        END { for (i = 1; i <= count; i++) if (!deleted[keys[i]]) print keys[i] "\t" records[keys[i]] }
    ' "$STATE_DIR/journal.tsv"
}

state_forget() { state_record "$1" "$2" '@deleted' '-'; }

state_has_active_records() {
    [ -f "$STATE_DIR/journal.tsv" ] || return 1
    state_validate || return $?
    awk -F '\t' '
        NR > 1 {
            deleted[$1 SUBSEP $2] = ($3 == "@deleted")
        }
        END {
            for (key in deleted) {
                if (!deleted[key]) exit 0
            }
            exit 1
        }
    ' "$STATE_DIR/journal.tsv"
}

state_cleanup() {
    if [ -f "$STATE_DIR/journal.tsv" ]; then
        if state_has_active_records; then
            report PRESENT 'State journal preserved for retained packages and runtimes'
            return 0
        fi
        run rm -f "$STATE_DIR/journal.tsv" || return $?
        report INSTALLED 'Removed dotfiles state journal'
    fi
}

record_package() {
    local provider=$1 package=$2 before=$3 eligibility=$4
    [ "$DRY_RUN" != 1 ] || return 0
    [ -z "$(state_value package "$provider:$package")" ] || return 0
    if [ "$before" = present ]; then
        state_record package "$provider:$package" preexisting protected
    else
        state_record package "$provider:$package" owned "$eligibility"
    fi
}