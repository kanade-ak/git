#!/bin/sh

test_description='pre-epoch raw dates in fast-import and fast-export'

. ./test-lib.sh
. "$TEST_DIRECTORY/lib-gpg.sh"

test_expect_success 'fast-import accepts negative raw committer dates' '
	git init preepoch &&
	(
		cd preepoch &&
		cat >stream <<-\EOF &&
		commit refs/heads/main
		author Meiji Importer <importer@example.com> -3061152000 +0900
		committer Meiji Importer <importer@example.com> -3061152000 +0900
		data <<MSG
		pre-epoch commit
		MSG
		M 644 inline file.txt
		data <<BLOB
		v1
		BLOB

		EOF
		git fast-import --date-format=raw <stream &&
		echo "-3061152000" >expect &&
		git log -1 --format=%ct refs/heads/main >actual &&
		test_cmp expect actual &&
		echo "-3061152000" >expect &&
		git log -1 --format=%at refs/heads/main >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'pre-epoch commits created by fast-import pass fsck' '
	git -C preepoch fsck 2>err &&
	test_must_be_empty err
'

test_expect_success 'raw date format rejects zero-padded negative timestamps' '
	git init padded &&
	(
		cd padded &&
		cat >stream <<-\EOF &&
		commit refs/heads/main
		committer Padded <padded@example.com> -0123 +0000
		data <<MSG
		zero-padded negative date
		MSG

		EOF
		test_must_fail git fast-import --date-format=raw <stream
	)
'

test_expect_success 'raw-permissive date format accepts zero-padded negative timestamps' '
	git init padded-permissive &&
	(
		cd padded-permissive &&
		cat >stream <<-\EOF &&
		commit refs/heads/main
		committer Padded <padded@example.com> -0123 +0000
		data <<MSG
		zero-padded negative date
		MSG

		EOF
		git fast-import --date-format=raw-permissive <stream &&
		echo "-123" >expect &&
		git log -1 --format=%ad --date=unix refs/heads/main >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'raw date format rejects a lone minus sign' '
	git init lone-minus &&
	(
		cd lone-minus &&
		cat >stream <<-\EOF &&
		commit refs/heads/main
		committer Broken <broken@example.com> - +0000
		data <<MSG
		broken date
		MSG

		EOF
		test_must_fail git fast-import --date-format=raw <stream
	)
'

test_expect_success 'fast-export round-trips pre-epoch dates' '
	git -C preepoch fast-export main >export &&
	grep -- "-3061152000 +0900" export &&
	git init reimport &&
	git -C reimport fast-import <export &&
	echo "-3061152000" >expect &&
	git -C reimport log -1 --format=%ct refs/heads/main >actual &&
	test_cmp expect actual
'

test_expect_success GPGSSH 'ssh signature verification works for pre-epoch committer dates' '
	test_config gpg.format ssh &&
	test_config user.signingkey "${GPGSSH_KEY_PRIMARY}" &&
	test_config gpg.ssh.allowedSignersFile "${GPGSSH_ALLOWED_SIGNERS}" &&
	GIT_AUTHOR_DATE="-3061152000 +0900" GIT_COMMITTER_DATE="-3061152000 +0900" \
		git commit --allow-empty -S -m "signed pre-epoch commit" &&
	git verify-commit HEAD &&
	echo G >expect &&
	git log -1 --format=%G? HEAD >actual &&
	test_cmp expect actual
'

test_done
