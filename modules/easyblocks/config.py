def can_build(env, platform):
    return True


def configure(env):
    pass


def get_doc_classes():
    return [
        "BlockLibrary",
        "BlockProgram",
        "BlockRunner",
    ]


def get_doc_path():
    return "doc_classes"
