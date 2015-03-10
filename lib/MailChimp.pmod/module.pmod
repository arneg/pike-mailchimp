#define MAILCHIMP_DEBUG

#ifdef MAILCHIMP_DEBUG
# define mc_debug(a ...)        werror(a)
#else
# define mc_debug(a ...)
#endif

typedef function(int(0..1),mapping|object(Error),mixed...:void) call_cb;
typedef function(int(0..1),array(mapping)|object(Error),mixed...:void) export_cb;

private void headers_ok() {}

constant permanent_errors = ([
    "List_DoesNotExist" : 1,
    "List_InvalidOption" : 1,
    "Invalid_ApiKey" : 1,
    "User_InvalidAction" : 1,
    "User_Disabled" : 1,
    "ValidationError" : 1,
]);

constant temporary_errors = ([
    "Too_Many_Connections" : 1,
    "User_UnderMaintenance" : 1,
    // we assume this is due to a connection problem or their api
    // is temporarily broken
    "invalid_json" : 1,
    "http_timeout" : 1,
]);

constant account_errors = ([
    "Invalid_ApiKey" : 1,
    "User_InvalidAction" : 1,
    "User_Disabled" : 1,
]);

constant list_errors = ([
    "List_DoesNotExist" : 1,
    "List_InvalidOption" : 1,
]);

constant segment_errors = ([
]);

class Error(mapping info) {
    string _sprintf(int type) {
        return sprintf("%O(%O)", this_program, info);
    }

    constant is_error = 1;

    int(0..1) `is_permanent() {
        return has_index(permanent_errors, info->name||info->code);
    }

    int(0..1) `is_temporary() {
        return has_index(temporary_errors, info->name||info->code);
    }

    int(0..1) `is_account_error() {
        return has_index(account_errors, info->name||info->code);
    }

    int(0..1) `is_list_error() {
        return has_index(list_errors, info->name||info->code);
    }

    int(0..1) `is_segment_error() {
        return has_index(segment_errors, info->name||info->code);
    }
}

class Timeout {
    inherit Error;

    void create() {
        ::create(([ "name" : "http_timeout",
                    "error" : "Could not connect to MailChimp API." ]));
    }
}

private object(Error) make_error(object(Error)|mapping data) {
    if (mappingp(data)) data = Error(data);
    return data;
}

private mapping get_email_struct(mapping|string data) {
    if (!mappingp(data)) data = ([ "email" : data ]);
    return data;
}


class Session {
    private void data_ok(object request, call_cb cb, array extra) {
        string s = request->data();
        mapping ret;
        
        // TODO: check return code

        if (catch (ret = Standards.JSON.decode(s))) {
            // TODO: test this case for real
            cb(0, Error(([ "name" : "invalid_json", "error" : describe_error(ret) ])), @extra);
            return;
        }

        if (mappingp(ret) && ret->status == "error") {
            cb(0, Error(ret), @extra);
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
            cb(0, Error(([ "name" : "invalid_json", "error" : describe_error(err) ])), @extra);
            return;
        }

        cb(1, ret, @extra);
    }

    private void fail(object request, export_cb|call_cb cb, array extra) {
        cb(0, Timeout(), @extra);
    }

    Protocols.HTTP.Session http = Protocols.HTTP.Session();
    Standards.URI url, export_url;

    string apikey;

    void create(string apikey) {
        array(string) tmp = apikey / "-";
        this_program::apikey = apikey;

        if (sizeof(tmp) != 2) error("Bad api key!\n");

        string dc = tmp[1];

        url = Standards.URI("https://"+dc+".api.mailchimp.com/2.0/");
        export_url = Standards.URI("https://"+dc+".api.mailchimp.com/export/1.0/");
    }

    void call(string s, mapping data, call_cb cb, mixed ... extra) {
        data += ([ "apikey" : apikey ]);

        mc_debug("api: %O %O\n", s, data);

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

private void list_cb(int(0..1) success, mapping data, object(Session) session,
                     function(array(List),mixed...:void) cb, array extra) {
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
        if (!objectp(session) || !mappingp(info) || !stringp(info->id)) error("Bad arguments.\n");
        id = info->id;
    }

    void call(string s, mapping data, call_cb cb, mixed ... extra) {
        session->call("lists/"+s, data + ([ "id" : id ]), cb, @extra);
    }

    private void export_callback(int(0..1) success, array(mapping)|object data, export_cb cb, array extra) {
        if (success) {
            cb(success, map(data[1..], Function.curry(mkmapping)(data[0])), @extra); 
        } else {
            cb(success, data, @extra);
        }
    }
    
    void export(mapping data, export_cb cb, mixed ... extra) {
        data += ([ "id" : id ]);

        if (objectp(data->since)) {
            data->since = data->since->set_timezone("UTC")->format_time();
        }
        session->export("list", data, export_callback, cb, extra);
    }

    void static_segments(void|mapping data, function(array(StaticSegment),mixed...:void) cb, mixed ... extra) {
        call("static-segments", data||([]), segment_cb, this, cb, extra);
    }

    void static_segment_add(string name, function(int(0..1),object(StaticSegment),mixed...:void) cb, mixed ... extra) {
        call("static-segment-add", ([ "name" : name ]), lambda(int(0..1) success, object(Error)|mapping data) {
             if (success) {
                cb(success, StaticSegment(this, data), @extra);
                return;
             }
             cb(success, make_error(data), @extra);
        });
    }

    string _sprintf(int type) {
        return sprintf("%O(%s)", this_program, id);
    }

    typedef subscribe_cb|function(array(object(Subscriber))|int(0..1),object(Error)|array(object(Error)),mixed...:void) member_info_cb;

    void member_info(string|mapping|array email, member_info_cb cb, mixed ... extra) {
        mapping data = ([]);
        int array_return = 0;
        if (stringp(email)) data->emails = ({ get_email_struct(email) });
        else if (mappingp(email)) data->emails = ({ email });
        else if (arrayp(email)) {
            array_return = 1;
            foreach (email; int i; string|mapping e) {
                if (stringp(e)) {
                    email[i]  = ([ "email" : e ]);
                }
            }
            data->emails = email;
        }

        call("member-info", data, lambda(int(0..1) success, object(Error)|mapping data) {
             if (!success || !mappingp(data) || !arrayp(data->data)) {
                cb(0, make_error(data), @extra);
                return;
             }

             if (array_return) {
                cb(map(data->data, Function.curry(Subscriber)(this)),
                   map(data->errors, Error), @extra);
             } else {
                if (data->success_count) {
                    cb(1, Subscriber(this, data->data[0]), @extra);
                } else {
                    cb(0, Error(data->errors[0]), @extra);
                }
             }
        });
    }

    typedef function(int(0..1),object(Subscriber)|object(Error),mixed...:void) subscribe_cb;

    void subscribe(string|mapping email, subscribe_cb cb,
                   mixed ... extra) {
        mapping data = ([
            "double_optin" : Val.false,
        ]);

        if (mappingp(email)) data += email;
        else data->email = get_email_struct(email);

        call("subscribe", data, lambda(int(0..1) success, object(Error)|mapping data) {
             if (!success || !mappingp(data) || !data->email || !data->euid || !data->leid) {
                cb(0, make_error(data), @extra);
                return;
             }

             cb(1, Subscriber(this, data), @extra);
        });
    }

    typedef function(int(0..1),object(Error),mixed...:void) unsubscribe_cb;

    void unsubscribe(string|mapping email, unsubscribe_cb cb, mixed ... extra) {
        mapping data = ([
            "send_goodye" : Val.false,
        ]);
        if (stringp(email)) data->email = get_email_struct(data);
        else data += email;
        call("unsubscribe", data, lambda(int(0..1) success, mapping data) {
             if (success && data->complete) {
                cb(1, 0, @extra);
             } else {
                cb(0, make_error(data), @extra);
             }
        });
    }

    typedef function(array(object(Subscriber))|int(0..1),
                     array(object(Error))|object(Error),mixed...:void) batch_subscribe_cb;

    void batch_subscribe(mapping data, array(mapping|string) batch, batch_subscribe_cb cb, mixed ... extra) {
        data = ([ "double_optin" : Val.false, ]) + data;

        if (!sizeof(batch)) error("Bad argument.\n");

        batch += ({ });

        foreach (batch; int i; mapping|string info) {
            if (stringp(info)) batch[i] = ([ "email" : get_email_struct(info) ]);
        }

        data->batch = batch;

        call("batch-subscribe", data, lambda(int(0..1) success, mapping data) {
            if (!success || !mappingp(data) || (!data->add_count && !data->update_count && !data->error_count)) {
                cb(0, make_error(data), @extra);
                return;
            } else {
                array(object) subs = map(data->adds + data->updates, Function.curry(Subscriber)(this));
                array(object) errors = map(data->errors, Error);

                cb(subs, errors, @extra);
            }
        });
    }

    typedef function(int(0..1),array(object(Error))|object(Error),mixed...:void) batch_unsubscribe_cb;

    void batch_unsubscribe(mapping data, array(mapping|string) batch, batch_unsubscribe_cb cb,
                           mixed ... extra) {
        if (!sizeof(batch)) error("Bad argument.\n");

        batch += ({ });

        foreach (batch; int i; mapping|string info) {
            if (stringp(info)) batch[i] = ([ "email" : get_email_struct(info) ]);
        }

        data->batch = batch;

        call("batch-unsubscribe", data, lambda(int(0..1) success, mapping data) {
            if (!success || !mappingp(data) || (!data->success_count && !data->error_count)) {
                cb(0, make_error(data), @extra);
                return;
            } else {
                array(object) errors = map(data->errors, Error);

                cb(1, errors, @extra);
            }
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
        if (!intp(info->id)) error("Bad argument.\n");
        id = info->id;
    }

    void call(string s, mapping data, call_cb cb, mixed ... extra) {
        list->call("static-segment-"+s, data + ([ "seg_id" : id ]), cb, @extra);
    }

    string _sprintf(int type) {
        return sprintf("%O(%O)", this_program, id);
    }

    void delete(call_cb cb, mixed ... extra) {
        call("del", ([]), cb, @extra);
    }

    typedef function(int(0..1),array(Error)|object(Error),mixed...:void) add_members_cb;

    void add_members(mixed|array members, add_members_cb cb, mixed ... extra) {
        if (!arrayp(members)) members = ({ members });
        if (!sizeof(members)) error("Bad argument.\n");
        foreach (members; int n; mixed v) {
            if (stringp(v)) members[n] = get_email_struct(v);
        }

        call("members-add", ([ "batch" : members ]), lambda(int(0..1) success, mapping|object(Error) ret) {
            if (!success || (!ret->success_count && !ret->error_count)) {
                cb(0, ret, @extra);
                return;
            }

            cb(1, map(ret->errors, make_error), @extra);
        });
    }

    typedef function(int(0..1),array(Error)|object(Error),mixed...:void) delete_members_cb;

    void delete_members(mixed|array members, delete_members_cb cb, mixed ... extra) {
        if (!arrayp(members)) members = ({ members });
        if (!sizeof(members)) error("Bad argument.\n");
        foreach (members; int n; mixed v) {
            if (stringp(v)) members[n] = get_email_struct(v);
        }

        call("members-del", ([ "batch" : members ]), lambda(int(0..1) success, object(Error)|mapping ret) {
            if (!success || (!ret->success_count && !ret->error_count)) {
                cb(0, ret, @extra);
                return;
            }

            cb(1, map(ret->errors, make_error), @extra);
        });
    }

    void reset(call_cb cb, mixed ... extra) {
        call("reset", ([ ]), cb, @extra);
    }
}
