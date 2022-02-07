vcl 4.0;

# Borrowed from mediawiki.org/wiki/Manual:Varnish_caching
# and modified for Canasta

backend default {
    .host = "web";
    .port = "80";
    .first_byte_timeout = 120s; 
    .connect_timeout = 30s; 
    .between_bytes_timeout = 120s;
}

acl purge {
    "web";
}

# vcl_recv is called whenever a request is received 
sub vcl_recv {
    # Serve objects up to 2 minutes past their expiry if the backend
    # is slow to respond.
    # set req.grace = 120s;

    set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;

    set req.backend_hint= default;

    # This uses the ACL action called "purge". Basically if a request to
    # PURGE the cache comes from anywhere other than localhost, ignore it.
    if (req.method == "PURGE") {
        if (!client.ip ~ purge) {
            return (synth(405, "Not allowed."));
        } else {
            return (purge);
        }
    }

    # Pass sitemaps
    if (req.url ~ "\.xml(\.gz)?$") {
        return (pass);
    }

    # Pass images
    if (req.url ~ "/w/images/") {
        return(pass);
    }

    # Pass parsoid
    if (req.url ~ "/w/rest.php/") {
        return(pass);
    }

    # Pass API
    if (req.url ~ "/w/api.php") {
        return(pass);
    }
    
    call mobile_detect;

    # Pass requests from logged-in users directly.
    # Only detect cookies with "session" and "Token" in file name, otherwise nothing get cached.
    if (req.http.Authorization || req.http.Cookie ~ "([sS]ession|Token)=") {
        return (pass);
    } /* Not cacheable by default */

    # Pass anything other than GET and HEAD directly.
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    } /* We only deal with GET and HEAD by default */

    # Force lookup if the request is a no-cache request from the client.
    if (req.http.Cache-Control ~ "no-cache") {
        ban(req.url);
    }

    # normalize Accept-Encoding to reduce vary
    if (req.http.Accept-Encoding) {
        if (req.http.User-Agent ~ "MSIE 6") {
        unset req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
        set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate") {
        set req.http.Accept-Encoding = "deflate";
        } else {
        unset req.http.Accept-Encoding;
        }
    }

    return (hash);
}

sub vcl_pipe {
        # Note that only the first request to the backend will have
        # X-Forwarded-For set.  If you use X-Forwarded-For and want to
        # have it set for all requests, make sure to have:
        # set req.http.connection = "close";
 
        # This is otherwise not necessary if you do not do any request rewriting.
 
        set req.http.connection = "close";
}

# Called if the cache has a copy of the page.
sub vcl_hit {
        if (!obj.ttl > 0s) {
            return (pass);
        }
}

# Called after a document has been successfully retrieved from the backend.
sub vcl_backend_response {
        # Don't cache 50x responses
        if (beresp.status == 500 || beresp.status == 502 || beresp.status == 503 || beresp.status == 504) {
            set beresp.uncacheable = true;
            return (deliver);
        }

       if (beresp.ttl < 48h) {
          set beresp.ttl = 48h;
        }       
 
        if (!beresp.ttl > 0s) {
          set beresp.uncacheable = true;
          return (deliver);
        }
 
        if (beresp.http.Set-Cookie) {
          set beresp.uncacheable = true;
          return (deliver);
        }
 
        if (beresp.http.Authorization && !beresp.http.Cache-Control ~ "public") {
          set beresp.uncacheable = true;
          return (deliver);
        }

        return (deliver);
}

sub mobile_detect {
    set req.http.X-Device = "pc";

    if ( (req.http.User-Agent ~ "(?i)(mobi|240x240|240x320|320x320|alcatel|android|audiovox|bada|benq|blackberry|cdm-|compal-|docomo|ericsson|hiptop|htc[-_]|huawei|ipod|kddi-|kindle|meego|midp|mitsu|mmp\/|mot-|motor|ngm_|nintendo|opera.m|palm|panasonic|philips|phone|playstation|portalmmm|sagem-|samsung|sanyo|sec-|semc-browser|sendo|sharp|silk|softbank|symbian|teleca|up.browser|vodafone|webos)"
            || req.http.User-Agent ~ "^(?i)(lge?|sie|nec|sgh|pg)-" || req.http.Accept ~ "vnd.wap.wml")
        && req.http.User-Agent !~ "(SMART-TV.*SamsungBrowser)" )
    {
        set req.http.X-Device = "mobile";
    }
}
