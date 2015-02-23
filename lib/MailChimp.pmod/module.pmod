#define MAILCHIMP_DEBUG

#ifdef MAILCHIMP_DEBUG
# define mc_debug(a ...)        werror(a)
#else
# define mc_debug(a ...)
#endif

typedef function(int(0..1),mapping|object(Error),mixed...:void) call_cb;
typedef function(int(0..1),array(mapping)|object(Error),mixed...:void) export_cb;

private void headers_ok() {}

class Error(mapping info) {
    string _sprintf(int type) {
        return sprintf("%O(%O)", this_program, info);
    }
}

class Timeout {
    inherit Error;

    void create() {
        ::create(([]));
    }
}

private void data_ok(object request, call_cb cb, array extra) {
    string s = request->data();
    mapping ret;
    
    // TODO: check return code

    if (catch (ret = Standards.JSON.decode(s))) {
        cb(0, 0, @extra);
        return;
    }

    if (mappingp(ret) && ret->status == "error") {
        cb(0, ret, @extra);
        return;
    }

    cb(1, ret, @extra);
}

private void export_data_ok(object request, export_cb cb, array extra) {
    string s = request->data();
    array ret = ({ });
    
    // TODO: check return code

    mixed err = catch {
        foreach (s/"\n";; string line) if (sizeof(line)) {
            ret += ({
                Standards.JSON.decode(line)
            });
        }
    };

    if (err) {
        cb(0, Error(([ "error" : err ])));
        return;
    }

    cb(1, ret, @extra);
}

private void fail(object request, export_cb|call_cb cb, array extra) {
    cb(0, Timeout(), @extra);
}


class Session {
    Protocols.HTTP.Session http = Protocols.HTTP.Session();
    Standards.URI url, export_url;

    string apikey;

    void create(string apikey) {
        this_program::apikey = apikey;

        string dc = (apikey/"-")[-1];

        url = Standards.URI("https://"+dc+".api.mailchimp.com/2.0/");
        export_url = Standards.URI("https://"+dc+".api.mailchimp.com/export/1.0/");
    }

    void call(string s, mapping data, call_cb cb, mixed ... extra) {
        data += ([ "apikey" : apikey ]);

        mc_debug("api: %O\n", s);

        http->async_post_url(Standards.URI(s+".json", url),
                             string_to_utf8(Standards.JSON.encode(data)),
                             headers_ok, data_ok, fail, cb, extra);
    }

    void export(string s, mapping data, call_cb cb, mixed ... extra) {
        data += ([ "apikey" : apikey ]);

        mc_debug("export: %O %O\n", s, data);

        http->async_get_url(Standards.URI(s, export_url), data,
                            headers_ok, export_data_ok, fail, cb, extra);
    }

    void lists(void|mapping data, function(array(List),mixed...:void) cb, mixed ... extra) {
        call("lists/list", data||([]), list_cb, this, cb, extra);
    }
}

private void list_cb(int(0..1) success, mapping data, object(Session) session, function(array(List),mixed...:void) cb, array extra) {
    if (!success || !arrayp(data->data)) {
        cb(0);
        return;
    }

    cb(map(data->data, Function.curry(List)(session)), @extra);
}

private void segment_cb(int(0..1) success, mixed data, object(List) list, function(array(StaticSegment), mixed...:void) cb, array extra) {
    if (!success || !arrayp(data)) {
        cb(0);
        return;
    }

    cb(map(data, Function.curry(StaticSegment)(list)), @extra);
}

class List {
    mapping info;
    string id;
    Session session;

    void create(Session session, mapping info) {
        this_program::session = session;
        this_program::info = info;
        id = info->id;
    }

    void call(string s, mapping data, call_cb cb, mixed ... extra) {
        session->call("lists/"+s, data + ([ "id" : id ]), cb, @extra);
    }
    
    void export(mapping data, export_cb cb, mixed ... extra) {
        data += ([ "id" : id ]);

        if (objectp(data->since)) {
            data->since = data->since->set_timezone("UTC")->format_time();
        }
        session->export("list", data, cb, @extra);
    }

    void static_segments(void|mapping data, function(array(StaticSegment),mixed...:void) cb, mixed ... extra) {
        call("static-segments", data||([]), segment_cb, this, cb, extra);
    }

    void static_segment_add(string name, function(object(StaticSegment),mixed...:void) cb, mixed ... extra) {
        call("static-segment-add", ([ "name" : name ]), lambda(int(0..1) success, mapping data) {
             if (success) {
                cb(StaticSegment(this, data), @extra);
                return;
             }
             cb(0, @extra);
        });
    }

    string _sprintf(int type) {
        return sprintf("%O(%s)", this_program, id);
    }

    void subscribe(string|mapping email, function(object(Subscriber)|int,void|object(Error):void) cb, mixed ... extra) {
        mapping data = ([
            "double_optin" : Val.false,
        ]);

        if (mappingp(email)) data += email;
        else data->email = ([ "email" : email ]);

        call("subscribe", data, lambda(int(0..1) success, mapping data) {
             if (!success || !mappingp(data) || !data->email || !data->euid || !data->leid) {
                cb(0, Error(data));
                return;
             }

             cb(Subscriber(this, data));
        });
    }
}

class Subscriber {
    List list;
    mapping info;

    void create(List list, mapping info) {
        this_program::list = list;
        this_program::info = info;
    }
}

class StaticSegment {
    int id;
    mapping info;
    List list;

    void create(List list, mapping info) {
        this_program::list = list;
        this_program::info = info;
        id = info->id;
    }

    void call(string s, mapping data, call_cb cb, mixed ... extra) {
        list->call("static-segment-"+s, data + ([ "seg_id" : id ]), cb, @extra);
    }

    string _sprintf(int type) {
        return sprintf("%O(%d)", this_program, id);
    }

    void delete(call_cb cb, mixed ... extra) {
        call("del", ([]), cb, @extra);
    }

    void add_members(mixed|array members, call_cb cb, mixed ... extra) {
        if (!arrayp(members)) members = ({ members });
        foreach (members; int n; mixed v) {
            if (stringp(v)) {
                // we assume its an email
                members[n] = ([ "email" : v ]);
            }
        }

        call("members-add", ([ "batch" : members ]), cb, @extra);
    }

    void delete_members(mixed|array members, call_cb cb, mixed ... extra) {
        if (!arrayp(members)) members = ({ members });
        foreach (members; int n; mixed v) {
            if (stringp(v)) {
                // we assume its an email
                members[n] = ([ "email" : v ]);
            }
        }

        call("members-del", ([ "batch" : members ]), cb, @extra);
    }

    void reset(call_cb cb, mixed ... extra) {
        call("reset", ([ ]), cb, @extra);
    }
}
