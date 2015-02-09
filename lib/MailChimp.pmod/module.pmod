typedef function(int(0..1),mapping,mixed...:void) call_cb;

void headers_ok() {}

void data_ok(object request, call_cb cb, array extra) {
    string s = request->data();
    mapping ret;

    if (catch (ret = Standards.JSON.decode(s))) {
        cb(0, 0, @extra);
        return;
    }

    if (!mappingp(ret) || ret->status == "error") {
        cb(0, ret, @extra);
        return;
    }

    cb(1, ret, @extra);
}

void fail(object request, call_cb cb, array extra) {
    cb(0, 0, @extra);
}


class Session {
    Protocols.HTTP.Session http = Protocols.HTTP.Session();
    Standards.URI url;

    string apikey;

    void create(string apikey) {
        this_program::apikey = apikey;

        string dc = (apikey/"-")[-1];

        url = Standards.URI("https://"+dc+".api.mailchimp.com/2.0/");
    }

    void call(string s, mapping data, call_cb cb, mixed ... extra) {
        data += ([ "apikey" : apikey ]);

        werror("api: %O\n", s);

        http->async_post_url(Standards.URI(s+".json", url),
                             string_to_utf8(Standards.JSON.encode(data)),
                             headers_ok, data_ok, fail, cb, extra);
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

private void segment_cb(int(0..1) success, mapping data, object(List) list, function(array(StaticSegment), mixed...:void) cb, array extra) {
    if (!success || !arrayp(data->data)) {
        cb(0);
        return;
    }

    cb(map(data->data, Function.curry(StaticSegment)(list)), @extra);
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

    void static_segments(void|mapping data, function(array(StaticSegment),mixed...:void) cb, mixed ... extra) {
        call("static-segments", data||([]), segment_cb, this, cb, extra);
    }
}

class StaticSegment {
    string id;
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
}
