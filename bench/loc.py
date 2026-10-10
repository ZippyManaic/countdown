#!/usr/bin/env python3
# Count lines of code in each solution, leaving out blank lines and comments
#
# Usage: bench/loc.py [language...]
#
# Count solver lines over the files that implement solve and total lines over all source except build files
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {"target", ".venv", "build", "out", "bin", "obj", "ebin", "zig-out", ".zig-cache", ".build",
             "__pycache__", "node_modules"}
SOURCE = {".py", ".rs", ".cu", ".s", ".c", ".h", ".cpp", ".hpp", ".zig", ".go", ".f90", ".pas", ".cob",
          ".lua", ".fs", ".mjs", ".adb", ".ads", ".java", ".cs", ".swift", ".kt", ".rb", ".lisp", ".hs",
          ".ml", ".bas", ".jl", ".erl", ".ex", ".exs"}
# Map each run.sh name to its project directory
PROJECTS = {
    "python": ".", "rust": "countdown-rs", "rust-par": "countdown-rs-par", "luajit": "countdown-lua",
    "gforth": "countdown-forth", "rubyjit": "countdown-ruby", "rust-par1": "countdown-rs-par",
}
# Name the solver files where the file name alone does not say
SOLVER_FILES = {
    "python": ["countdown.py"], "rust": ["src/main.rs"], "table": ["solver.py", "build_table.py", "pools.py"],
    "ml": ["solver.py", "model.py", "tokens.py"], "wasm": ["../countdown-c/solver.c", "compat/immintrin.h"],
}
# Leave out files the build generates from others
GENERATED = {"countdown-basic/countdown.bas"}
ALL = ("python table torch ml cuda rust asm c cpp zig go fortran pascal cobol lua forth js ada java csharp "
       "swift wasm fsharp kotlin ruby lisp haskell ocaml freebasic basic julia erlang elixir "
       "c-par rust-par go-par java-par julia-par erlang-par elixir-par").split()

LINE = {".py": "#", ".rb": "#", ".jl": "#", ".ex": "#", ".exs": "#", ".s": "#", ".lua": "--", ".hs": "--",
        ".adb": "--", ".ads": "--", ".erl": "%", ".f90": "!", ".cob": "*>", ".lisp": ";", ".bas": "'",
        ".ml": None}
BLOCK = {".c": ("/*", "*/"), ".h": ("/*", "*/"), ".cpp": ("/*", "*/"), ".hpp": ("/*", "*/"),
         ".cu": ("/*", "*/"), ".rs": ("/*", "*/"), ".go": ("/*", "*/"), ".java": ("/*", "*/"),
         ".cs": ("/*", "*/"), ".swift": ("/*", "*/"), ".kt": ("/*", "*/"), ".mjs": ("/*", "*/"),
         ".zig": None, ".s": ("/*", "*/"), ".hs": ("{-", "-}"), ".ml": ("(*", "*)"), ".pas": ("{", "}"),
         ".lisp": ("#|", "|#"), ".lua": ("--[[", "]]"), ".jl": ("#=", "=#")}


def comment_syntax(path):
    ext = os.path.splitext(path)[1]
    # Tell F# from Forth since both use the .fs extension
    if ext == ".fs":
        return ("\\", None) if "forth" in path else ("//", ("(*", "*)"))
    line = LINE.get(ext, "//")
    if ext == ".bas" and "countdown-basic" in path:
        line = "REM"
    return line, BLOCK.get(ext)


def count(path):
    line_mark, block = comment_syntax(path)
    n, inside = 0, False
    for raw in open(path, errors="replace"):
        text = raw.strip()
        if inside:
            if block[1] in text:
                inside = False
                text = text.split(block[1], 1)[1].strip()
            else:
                continue
        if block and text.startswith(block[0]) and block[1] not in text[len(block[0]):]:
            inside = True
            continue
        if block and text.startswith(block[0]):
            text = text.split(block[1], 1)[1].strip()
        if not text:
            continue
        # Treat numbered BASIC lines whose statement is REM as comments
        if line_mark == "REM" and re.match(r"^\d*\s*REM\b", text, re.I):
            continue
        if line_mark and line_mark != "REM" and text.startswith(line_mark):
            continue
        n += 1
    return n


def files(lang):
    project = os.path.join(ROOT, PROJECTS.get(lang, "countdown-" + lang))
    if lang == "python":
        return [os.path.join(ROOT, "countdown.py")], [os.path.join(ROOT, "countdown.py")]
    found = []
    for base, dirs, names in os.walk(project):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        found += [os.path.join(base, n) for n in names if os.path.splitext(n)[1] in SOURCE
                  and os.path.relpath(os.path.join(base, n), ROOT) not in GENERATED]
    if lang in SOLVER_FILES:
        solver = [os.path.normpath(os.path.join(project, f)) for f in SOLVER_FILES[lang]]
    else:
        solver = [f for f in found if re.match(r"(solver|parsolver|pool|lib\.rs)", os.path.basename(f).lower())
                  or "/kernels/" in f]
    # Include files from another project, such as the C solver WebAssembly compiles, in both counts
    return solver, sorted(set(found) | set(solver))


def main():
    langs = sys.argv[1:] or ALL
    print("| Solution | Solver lines | Total lines |")
    print("|---|---|---|")
    for lang in langs:
        solver, total = files(lang)
        print(f"| {lang} | {sum(map(count, solver)):,} | {sum(map(count, total)):,} |")


if __name__ == "__main__":
    main()
