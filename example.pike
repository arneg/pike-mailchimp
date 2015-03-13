MailChimp.Session session;

void cb(int success, mapping data) {
    werror("%O %O\n", success, data);
}

void segment_cb(array(object) segments) {
    werror("segments: %O\n", segments);
}

void list_cb(array(object) lists) {
    werror("lists: %O\n", lists);
    lists->static_segments(0, segment_cb);
    lists->export(([]), cb);
}

int main(int argc, array(string) argv) {
    session = MailChimp.Session(argv[1]);

    session->call("helper/ping", ([]), cb);
    session->lists(0, list_cb);

    return -1;
}
