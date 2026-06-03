#!/bin/sh

test_description='kanade.one remote whitelist'

. ./test-lib.sh

test_expect_success 'local remotes are allowed' '
	git init --bare local.git &&
	git ls-remote local.git >actual &&
	test_must_be_empty actual
'

test_expect_success 'non-kanade HTTP remotes are rejected before access' '
	test_must_fail git ls-remote https://example.com/repo.git 2>err &&
	test_grep "only kanade.one remotes are allowed" err
'

test_expect_success 'non-kanade SSH-style remotes are rejected before access' '
	test_must_fail git fetch-pack --diag-url git@example.com:repo 2>err &&
	test_grep "only kanade.one remotes are allowed" err
'

test_expect_success 'non-kanade file URL authorities are rejected' '
	test_must_fail git fetch-pack --diag-url file://example.com/repo 2>err &&
	test_grep "only kanade.one remotes are allowed" err
'

test_expect_success 'remote helpers cannot hide arbitrary destinations' '
	test_must_fail git ls-remote helper::elsewhere 2>err &&
	test_grep "only kanade.one remotes are allowed" err
'

test_expect_success 'clone is not restricted by the kanade.one whitelist' '
	rm -rf clone-helper &&
	helper_env="$PWD/helper-env" &&
	write_script git-remote-helper <<-EOF &&
	echo "\${GIT_KANADE_CLONE_REMOTE_ACCESS-unset}" >"$helper_env"
	exit 1
	EOF
	test_must_fail env PATH="$PWD:$PATH" \
		git clone helper::elsewhere clone-helper 2>err &&
	echo 1 >expect &&
	test_cmp expect helper-env &&
	test_grep "remote helper" err &&
	! grep "only kanade.one remotes are allowed" err
'

test_expect_success 'kanade.one SSH-style remotes are accepted by URL parser' '
	git fetch-pack --diag-url git@kanade.one:repo >actual &&
	test_grep "userandhost=git@kanade.one" actual
'

test_expect_success 'kanade.one subdomains are accepted by URL parser' '
	git fetch-pack --diag-url git@git.kanade.one:repo >actual &&
	test_grep "userandhost=git@git.kanade.one" actual
'

test_expect_success 'push to non-kanade remotes is rejected before access' '
	git init push-src &&
	test_commit -C push-src base &&
	test_must_fail env GIT_KANADE_CLONE_REMOTE_ACCESS=1 \
		git -C push-src push https://example.com/repo.git HEAD 2>err &&
	test_grep "only kanade.one remotes are allowed" err
'

test_done
