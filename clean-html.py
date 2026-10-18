#!/usr/bin/env python3
"""
clean-html.py

Strips old static-site-generator HTML wrappers from v2/input/*.md files:

1. Gallery wrapper files: remove <pre>, <div style=...>, <div>, </div>,
   <p style="clear:both">, <br>, </img> scaffolding while keeping images/captions.
2. assembly-basics.md: delete commented-out <style> and <svg> blocks.
3. led-cube.md: remove <center>/<\/center> around the image.
4. koblenz-freiburg-by-bike.md: convert <a href="...">text</a> → [text](...)
"""

import re
from pathlib import Path

INPUT = Path(__file__).parent / "input"


# ── Gallery wrapper cleanup ──────────────────────────────────────────────────

GALLERY_FILES = [
    "windsurf.md", "defcon30.md", "cccamp19.md", "blackhat-2022.md",
    "egypt.md", "emf-camp-eastnor.md", "troopers-heidelberg.md",
    "windsurf-portugal.md", "koblenz-freiburg-by-bike.md",
    "bountyconedu-madrid.md", "gpn20.md", "mch-zeewolde.md",
    "36c3.md", "gpn17.md", "gpn18.md", "gpn19.md", "rhodos.md",
    "ski-obertauern.md", "wakeboarding-wedau.md",
]


def clean_gallery_line(line):
    s = line.strip()

    # Lines that are pure wrapper tags → drop (return None)
    if s in ("</pre>", "<pre>", "<br>", "</div>"):
        return None
    if re.match(r'^<p\b[^>]*>\s*</p>$', s):
        return None
    if re.match(r'^<div\b[^>]*>\s*$', s):
        return None

    # <a href="...">text</a> → [text](...)
    line = re.sub(r'<a\s+href="([^"]+)">([^<]+)</a>', r'[\2](\1)', line)

    # Remove </img>
    line = line.replace('</img>', '')

    # <div>content</div> → content (strip wrapping div+whitespace)
    line = re.sub(r'^\s*<div>\s*(.*?)\s*</div>\s*$', r'\1', line)

    # Strip leading whitespace (was indented inside div wrappers)
    content = line.strip()
    if content == '':
        return ''
    return content


def clean_gallery(text):
    lines = text.split('\n')
    out = []
    for line in lines:
        result = clean_gallery_line(line)
        if result is not None:
            out.append(result)

    # Collapse runs of 3+ blank lines to 1
    final = []
    blank_run = 0
    for line in out:
        if line == '':
            blank_run += 1
            if blank_run <= 1:
                final.append(line)
        else:
            blank_run = 0
            final.append(line)
    return '\n'.join(final)


# ── assembly-basics.md: remove commented-out blocks ─────────────────────────

def clean_assembly(text):
    # Remove <!--<style>...</style>--> block (possibly multi-line)
    text = re.sub(r'\s*<!--<style>.*?</style>-->\n?', '\n', text, flags=re.DOTALL)
    # Remove <!--</pre><svg ...>...</svg><pre>--> block
    text = re.sub(r'\s*<!--</pre>.*?<pre>-->\n?', '\n', text, flags=re.DOTALL)
    # Remove standalone </pre> and <pre> lines that are just wrapper artifacts
    text = re.sub(r'^</pre>\n', '', text, flags=re.MULTILINE)
    text = re.sub(r'^<pre>\n', '', text, flags=re.MULTILINE)
    # Collapse 3+ blank lines
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text


# ── led-cube.md: remove <center> wrapper ────────────────────────────────────

def clean_led_cube(text):
    text = re.sub(r'^<center>\n', '', text, flags=re.MULTILINE)
    text = re.sub(r'^</center>\n', '', text, flags=re.MULTILINE)
    return text


# ── main ─────────────────────────────────────────────────────────────────────

def process(filename, fn):
    path = INPUT / filename
    original = path.read_text(encoding="utf-8")
    result = fn(original)
    if result != original:
        path.write_text(result, encoding="utf-8")
        print(f"  cleaned  {filename}")
    else:
        print(f"  no-op    {filename}")


def main():
    for f in GALLERY_FILES:
        process(f, clean_gallery)
    process("assembly-basics.md", clean_assembly)
    process("led-cube.md", clean_led_cube)


if __name__ == "__main__":
    main()
