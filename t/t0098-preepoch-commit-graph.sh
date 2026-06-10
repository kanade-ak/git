#!/bin/sh

test_description='commit-graph with pre-epoch commit dates'

. ./test-lib.sh

test_expect_success 'set up history reaching back before the epoch' '
	git init repo &&
	(
		cd repo &&
		cat >stream <<-\EOF &&
		commit refs/heads/main
		mark :1
		committer History Builder <builder@example.com> -3061152000 +0900
		data <<MSG
		meiji era
		MSG
		M 644 inline law.txt
		data <<BLOB
		v1
		BLOB

		commit refs/heads/main
		mark :2
		committer History Builder <builder@example.com> -86400 +0000
		data <<MSG
		day before the epoch
		MSG
		M 644 inline law.txt
		data <<BLOB
		v2
		BLOB

		commit refs/heads/main
		mark :3
		committer History Builder <builder@example.com> 0 +0000
		data <<MSG
		the epoch itself
		MSG
		M 644 inline law.txt
		data <<BLOB
		v3
		BLOB

		commit refs/heads/main
		mark :4
		committer History Builder <builder@example.com> 86400 +0000
		data <<MSG
		day after the epoch
		MSG
		M 644 inline law.txt
		data <<BLOB
		v4
		BLOB

		commit refs/heads/main
		mark :5
		committer History Builder <builder@example.com> 1700000000 +0000
		data <<MSG
		recent commit
		MSG
		M 644 inline law.txt
		data <<BLOB
		v5
		BLOB

		EOF
		git fast-import --date-format=raw <stream
	)
'

test_expect_success 'commit-graph write includes pre-epoch commits' '
	git -C repo commit-graph write --reachable &&
	test_path_is_file repo/.git/objects/info/commit-graph &&
	test-tool -C repo read-graph >output &&
	grep "num_commits: 5" output
'

test_expect_success 'commit-graph verify accepts clamped pre-epoch dates' '
	git -C repo commit-graph verify
'

test_expect_success 'commit dates are not distorted by the commit-graph' '
	cat >expect <<-\EOF &&
	1700000000
	86400
	0
	-86400
	-3061152000
	EOF
	git -C repo log --format=%ct main >actual &&
	test_cmp expect actual &&
	git -C repo -c core.commitGraph=false log --format=%ct main >no_graph &&
	test_cmp expect no_graph
'

test_expect_success 'date-limited traversal matches with and without commit-graph' '
	for range in \
		"--until=1900-01-01T00:00:00+0000" \
		"--until=1969-12-31T00:00:00+0000" \
		"--since=1970-01-02T00:00:00+0000" \
		"--since=1880-01-01T00:00:00+0000 --until=1971-01-01T00:00:00+0000"
	do
		git -C repo rev-list $range main >with_graph &&
		git -C repo -c core.commitGraph=false rev-list $range main >without_graph &&
		test_cmp with_graph without_graph || return 1
	done
'

test_expect_success 'pre-epoch boundary commit is found by --until' '
	git -C repo rev-list --until=1900-01-01T00:00:00+0000 main >actual &&
	test_line_count = 1 actual
'

test_expect_success 'incremental split commit-graph on top of pre-epoch layer' '
	(
		cd repo &&
		cat >stream2 <<-\EOF &&
		commit refs/heads/main
		committer History Builder <builder@example.com> 1700086400 +0000
		data <<MSG
		newer commit
		MSG
		from refs/heads/main^0
		M 644 inline law.txt
		data <<BLOB
		v6
		BLOB

		EOF
		git fast-import --date-format=raw <stream2 &&
		git commit-graph write --reachable --split &&
		git commit-graph verify &&
		git log --format=%ct -2 main >actual &&
		cat >expect <<-\EOF &&
		1700086400
		1700000000
		EOF
		test_cmp expect actual
	)
'

test_expect_success 'graph-backed generation data stays self-consistent' '
	git -C repo commit-graph write --reachable &&
	git -C repo commit-graph verify &&
	git -C repo log --format=%ct main >after &&
	git -C repo -c core.commitGraph=false log --format=%ct main >expect &&
	test_cmp expect after
'

test_expect_success 'generations stay monotonic for far-future dates beyond 32 bits' '
	git init future &&
	(
		cd future &&
		cat >stream <<-\EOF &&
		commit refs/heads/main
		committer History Builder <builder@example.com> -3061152000 +0900
		data <<MSG
		pre-epoch root
		MSG
		M 644 inline law.txt
		data <<BLOB
		v1
		BLOB

		commit refs/heads/main
		committer History Builder <builder@example.com> 4670362800 +0900
		data <<MSG
		scheduled twenty-second century revision 1
		MSG
		M 644 inline law.txt
		data <<BLOB
		v2
		BLOB

		commit refs/heads/main
		committer History Builder <builder@example.com> 4670362800 +0900
		data <<MSG
		scheduled twenty-second century revision 2
		MSG
		M 644 inline law.txt
		data <<BLOB
		v3
		BLOB

		commit refs/heads/main
		committer History Builder <builder@example.com> 4670362800 +0900
		data <<MSG
		scheduled twenty-second century revision 3
		MSG
		M 644 inline law.txt
		data <<BLOB
		v4
		BLOB

		EOF
		git fast-import --date-format=raw <stream &&
		git commit-graph write --reachable &&
		git commit-graph verify &&
		git log --format=%ct main >actual &&
		cat >expect <<-\EOF &&
		4670362800
		4670362800
		4670362800
		-3061152000
		EOF
		test_cmp expect actual
	)
'

test_done
