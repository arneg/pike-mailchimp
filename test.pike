MailChimp.Session session;

void cb(int success, mapping data) {
    werror("%O %O\n", success, data);
}

void segment_cb(array(object) segments) {
    werror("segments: %O\n", segments);
    segments->add_members("foo2@laramies.com", cb);
}

void list_cb(array(object) lists) {
    werror("lists: %O\n", lists);
    lists->static_segments(0, segment_cb);
    lists->subscribe("foo2@laramies.com", cb);
    //lists->static_segment_add("foo", cb);
    lists->export(([]), cb);
}

int main(int argc, array(string) argv) {
    session = MailChimp.Session(argv[1]);

    session->call("helper/ping", ([]), cb);
    session->lists(0, list_cb);

    return -1;
}
