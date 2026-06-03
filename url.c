#include "git-compat-util.h"
#include "abspath.h"
#include "hex-ll.h"
#include "strbuf.h"
#include "url.h"

int is_rfc3986_unreserved(char ch)
{
	return isalnum(ch) ||
		ch == '-' || ch == '_' || ch == '.' || ch == '~';
}

int is_casefolding_rfc3986_unreserved(char c)
{
	return (c >= 'a' && c <= 'z') ||
	       (c >= '0' && c <= '9') ||
	       c == '-' || c == '.' || c == '_' || c == '~';
}

int is_urlschemechar(int first_flag, int ch)
{
	/*
	 * The set of valid URL schemes, as per STD66 (RFC3986) is
	 * '[A-Za-z][A-Za-z0-9+.-]*'. But use slightly looser check
	 * of '[A-Za-z0-9][A-Za-z0-9+.-]*' because earlier version
	 * of check used '[A-Za-z0-9]+' so not to break any remote
	 * helpers.
	 */
	int alphanumeric, special;
	alphanumeric = ch > 0 && isalnum(ch);
	special = ch == '+' || ch == '-' || ch == '.';
	return alphanumeric || (!first_flag && special);
}

int is_url(const char *url)
{
	/* Is "scheme" part reasonable? */
	if (!url || !is_urlschemechar(1, *url++))
		return 0;
	while (*url && *url != ':') {
		if (!is_urlschemechar(0, *url++))
			return 0;
	}
	/* We've seen "scheme"; we want colon-slash-slash */
	return (url[0] == ':' && url[1] == '/' && url[2] == '/');
}

static char *url_decode_internal(const char **query, int len,
				 const char *stop_at, struct strbuf *out,
				 int decode_plus)
{
	const char *q = *query;

	while (len) {
		unsigned char c = *q;

		if (!c)
			break;
		if (stop_at && strchr(stop_at, c)) {
			q++;
			len--;
			break;
		}

		if (c == '%' && (len < 0 || len >= 3)) {
			int val = hex2chr(q + 1);
			if (0 < val) {
				strbuf_addch(out, val);
				q += 3;
				len -= 3;
				continue;
			}
		}

		if (decode_plus && c == '+')
			strbuf_addch(out, ' ');
		else
			strbuf_addch(out, c);
		q++;
		len--;
	}
	*query = q;
	return strbuf_detach(out, NULL);
}

char *url_decode(const char *url)
{
	return url_decode_mem(url, strlen(url));
}

char *url_decode_mem(const char *url, int len)
{
	struct strbuf out = STRBUF_INIT;
	const char *colon = memchr(url, ':', len);

	/* Skip protocol part if present */
	if (colon && url < colon) {
		strbuf_add(&out, url, colon - url);
		len -= colon - url;
		url = colon;
	}
	return url_decode_internal(&url, len, NULL, &out, 0);
}

char *url_percent_decode(const char *encoded)
{
	struct strbuf out = STRBUF_INIT;
	return url_decode_internal(&encoded, strlen(encoded), NULL, &out, 0);
}

char *url_decode_parameter_name(const char **query)
{
	struct strbuf out = STRBUF_INIT;
	return url_decode_internal(query, -1, "&=", &out, 1);
}

char *url_decode_parameter_value(const char **query)
{
	struct strbuf out = STRBUF_INIT;
	return url_decode_internal(query, -1, "&", &out, 1);
}

void end_url_with_slash(struct strbuf *buf, const char *url)
{
	strbuf_addstr(buf, url);
	strbuf_complete(buf, '/');
}

void str_end_url_with_slash(const char *url, char **dest)
{
	struct strbuf buf = STRBUF_INIT;
	end_url_with_slash(&buf, url);
	free(*dest);
	*dest = strbuf_detach(&buf, NULL);
}

int url_is_local_not_ssh(const char *url)
{
	const char *colon = strchr(url, ':');
	const char *slash = strchr(url, '/');
	return !colon || (slash && slash < colon) ||
		(has_dos_drive_prefix(url) && is_valid_path(url));
}

static int kanade_host_matches(const char *host, size_t len)
{
	const char suffix[] = "kanade.one";
	size_t suffix_len = strlen(suffix);

	if (len >= 2 && host[0] == '[' && host[len - 1] == ']')
		return 0;

	while (len && host[len - 1] == '.')
		len--;

	if (len == suffix_len)
		return !strncasecmp(host, suffix, suffix_len);
	if (len > suffix_len + 1 &&
	    host[len - suffix_len - 1] == '.' &&
	    !strncasecmp(host + len - suffix_len, suffix, suffix_len))
		return 1;
	return 0;
}

static const char *find_last_at_before(const char *start, const char *end)
{
	const char *at = NULL;

	for (; start < end; start++) {
		if (*start == '@')
			at = start;
	}
	return at;
}

static int kanade_check_url_host(const char *host, const char *end)
{
	const char *at;

	if (host >= end)
		return 0;

	at = find_last_at_before(host, end);
	if (at)
		host = at + 1;

	if (host >= end)
		return 0;

	if (*host == '[') {
		const char *close = memchr(host, ']', end - host);
		if (!close)
			return 0;
		end = close + 1;
	} else {
		const char *colon = memchr(host, ':', end - host);
		if (colon)
			end = colon;
	}

	return kanade_host_matches(host, end - host);
}

int url_is_allowed_by_kanade_whitelist(const char *url)
{
	const char *p = url;
	const char *scheme_end, *host, *end;
	int helper_url = 0;

	if (!p || !*p)
		return 1;

	/*
	 * Remote-helper URLs are of the form "helper::real-url". Check the
	 * real URL so helpers cannot hide an unapproved network destination.
	 */
	scheme_end = strstr(p, "::");
	if (scheme_end) {
		helper_url = 1;
		p = scheme_end + 2;
	}

	if (url_is_local_not_ssh(p)) {
		if (helper_url && !is_absolute_path(p) &&
		    !starts_with(p, "./") && !starts_with(p, "../"))
			return 0;
		return 1;
	}

	if (is_url(p)) {
		scheme_end = strstr(p, "://");
		host = scheme_end + 3;
		end = host + strcspn(host, "/?#");

		if (scheme_end == p + 4 && !strncasecmp(p, "file", 4)) {
			if (host == end || has_dos_drive_prefix(host))
				return 1;
			if (end - host == 9 && !strncasecmp(host, "localhost", 9))
				return 1;
			return kanade_check_url_host(host, end);
		}

		return kanade_check_url_host(host, end);
	}

	end = strchr(p, ':');
	if (!end)
		return 1;

	return kanade_check_url_host(p, end);
}

enum url_scheme url_get_scheme(const char *name)
{
	if (!strcmp(name, "ssh"))
		return URL_SCHEME_SSH;
	if (!strcmp(name, "git"))
		return URL_SCHEME_GIT;
	if (!strcmp(name, "git+ssh")) /* deprecated - do not use */
		return URL_SCHEME_SSH;
	if (!strcmp(name, "ssh+git")) /* deprecated - do not use */
		return URL_SCHEME_SSH;
	if (!strcmp(name, "file"))
		return URL_SCHEME_FILE;
	return URL_SCHEME_UNKNOWN;
}
