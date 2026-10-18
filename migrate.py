#!/usr/bin/env python3
"""
migrate.py

Reads pages from the old emile.space tree structure (in/) and copies them into
the new flat wiki structure (v2/input/), prepending a (meta ...) header.

Also generates:
  - v2/MIGRATION.md        (checklist, updated in place)
  - v2/nginx/redirects.conf (301 map for old → new URLs)
"""

import os
import re
from pathlib import Path
from datetime import date

OLD = Path("/Users/emile/emile.space/in")
NEW = Path("/Users/emile/emile.space/v2/input")
TODAY = date.today().isoformat()

# ---------------------------------------------------------------------------
# Mapping: (old_rel_path, new_name, tags, published, event_date, info_keys)
#
#   old_rel_path  – path relative to OLD, always ends in README.md
#   new_name      – flat filename without .md
#   tags          – list of tag strings
#   published     – ISO date for published meta
#   event_date    – ISO date for "date" meta (events/talks only), or None
#   info_keys     – keys shown in info bar, or []
# ---------------------------------------------------------------------------
PAGES = [
    # ── Top-level / section indexes ─────────────────────────────────────
    ("README.md",                         "index",           ["navbar"],                           "2026-09-14", None,         []),
    ("about/README.md",                   "about",           ["navbar"],                           "2026-09-14", None,         []),
    ("blog/README.md",                    "blog",            ["navbar"],                           "2026-09-14", None,         []),
    ("ctf/README.md",                     "ctf",             ["navbar"],                           "2026-09-14", None,         []),
    ("events/README.md",                  "events",          ["navbar"],                           "2026-09-14", None,         []),
    ("projects/README.md",                "projects",        ["navbar"],                           "2026-09-14", None,         []),
    ("projects.md",                       "projects",        ["navbar"],                           "2026-09-14", None,         []),  # root-level duplicate, skip
    ("publications/README.md",            "publications",    ["publication"],                      "2026-09-14", None,         []),
    ("sport/README.md",                   "sport",           ["navbar"],                           "2026-09-14", None,         []),
    ("talks/README.md",                   "talks",           ["talk"],                             "2026-09-14", None,         []),
    ("workshops/README.md",               "workshops",       ["workshop"],                         "2026-09-14", None,         []),
    ("irc/README.md",                     "irc",             ["project"],                          "2026-09-14", None,         []),
    ("files/README.md",                   "files",           ["files"],                            "2026-09-14", None,         []),
    ("search/README.md",                  "search",          [],                                   "2026-09-14", None,         []),

    # ── Blog posts ───────────────────────────────────────────────────────
    ("blog/2020/09-26-nixops/README.md",                        "nixops",                         ["blog","nix"],              "2020-09-26", None, ["tag","published"]),
    ("blog/2020/10-10-r2wars/README.md",                        "r2wars",                         ["blog","ctf","r2wars"],     "2020-10-10", None, ["tag","published"]),
    ("blog/2020/11-15-nixctf/README.md",                        "nixctf",                         ["blog","nix","ctf"],        "2020-11-15", None, ["tag","published"]),
    ("blog/2021/02-04-menger-sponge/README.md",                 "menger-sponge",                  ["blog","origami"],          "2021-02-04", None, ["tag","published"]),
    ("blog/2021/02-05-turing-bot/README.md",                    "turing-bot",                     ["blog","ai","rust"],        "2021-02-05", None, ["tag","published"]),
    ("blog/2021/06-14-personal-websites/README.md",             "personal-websites",              ["blog"],                    "2021-06-14", None, ["tag","published"]),
    ("blog/2021/07-12-monorepo/README.md",                      "monorepo",                       ["blog","nix"],              "2021-07-12", None, ["tag","published"]),
    ("blog/2021/12-26-interpaleki/README.md",                   "interpaleki",                    ["blog"],                    "2021-12-26", None, ["tag","published"]),
    ("blog/2021/12-26-relaunch/README.md",                      "relaunch",                       ["blog"],                    "2021-12-26", None, ["tag","published"]),
    ("blog/2021/12-30-relaunch-thoughts/README.md",             "relaunch-thoughts",              ["blog"],                    "2021-12-30", None, ["tag","published"]),
    ("blog/2022/01-03-offline-rust-stdlib-docs/README.md",      "offline-rust-stdlib-docs",       ["blog","rust","stdlib"],    "2022-01-03", None, ["tag","published"]),
    ("blog/2022/01-29-incremental-builds/README.md",            "incremental-builds",             ["blog","nix"],              "2022-01-29", None, ["tag","published"]),
    ("blog/2022/06-09-nix-like-structures-elsewhere/README.md", "nix-like-structures-elsewhere",  ["blog","nix"],              "2022-06-09", None, ["tag","published"]),
    ("blog/2022/09-01-public-git-via-ssh/README.md",            "public-git-via-ssh",             ["blog","git","ssh"],        "2022-09-01", None, ["tag","published"]),
    ("blog/2022/10-03-plan9-cluster-init/README.md",            "plan9-cluster-init",             ["blog","plan9"],            "2022-10-03", None, ["tag","published"]),
    ("blog/2022/11-03-backlinks/README.md",                     "backlinks",                      ["blog","vokobe"],           "2022-11-03", None, ["tag","published"]),
    ("blog/2022/11-06-migrating-to-flat-hierarchy/README.md",   "migrating-to-flat-hierarchy",    ["blog","vokobe"],           "2022-11-06", None, ["tag","published"]),
    ("blog/2022/11-10-web-of-trust-social-groups/README.md",    "web-of-trust-social-groups",     ["blog"],                   "2022-11-10", None, ["tag","published"]),
    ("blog/2024/05-11-lampadas/README.md",                      "lampadas",                       ["blog","lisp"],             "2024-05-11", None, ["tag","published"]),
    ("blog/2024/12-16-web-of-trust/README.md",                  "web-of-trust",                   ["blog"],                   "2024-12-16", None, ["tag","published"]),
    ("blog/2025/02-23-nix-flake-template-hydra-foo/README.md",  "nix-flake-template-hydra-foo",   ["blog","nix"],              "2025-02-23", None, ["tag","published"]),
    ("blog/2026/01-17-photo-orga/README.md",                    "photo-orga",                     ["blog","photos"],           "2026-01-17", None, ["tag","published"]),

    # ── Events ───────────────────────────────────────────────────────────
    ("events/2000/07_birth/README.md",                                  "birth",                          ["event"],       "2000-07-01",  "2000-07-01",  ["tag","date"]),
    ("events/2012/08_korsika/README.md",                                "korsika",                        ["event"],       "2012-08-01",  "2012-08-01",  ["tag","date"]),
    ("events/2017/04_lausanne/README.md",                               "lausanne-ski-2017",              ["event","ski"], "2017-04-01",  "2017-04-01",  ["tag","date"]),
    ("events/2017/05_gpn17/README.md",                                  "gpn17",                          ["event","gpn"], "2017-05-01",  "2017-05-01",  ["tag","date"]),
    ("events/2017/06_changes_award/README.md",                          "changes-award",                  ["event"],       "2017-06-01",  "2017-06-01",  ["tag","date"]),
    ("events/2017/07_dolomiten/README.md",                              "dolomiten",                      ["event"],       "2017-07-01",  "2017-07-01",  ["tag","date"]),
    ("events/2017/07_ich_und_wir_projekt/README.md",                    "ich-und-wir-projekt-2017",       ["event"],       "2017-07-01",  "2017-07-01",  ["tag","date"]),
    ("events/2017/12_34c3/README.md",                                   "34c3",                           ["event","ccc"], "2017-12-27",  "2017-12-27",  ["tag","date"]),
    ("events/2018/01_ich_und_wir_projekt/README.md",                    "ich-und-wir-projekt-2018",       ["event"],       "2018-01-01",  "2018-01-01",  ["tag","date"]),
    ("events/2018/03_ski_obertauern/README.md",                         "ski-obertauern",                 ["event","ski"], "2018-03-01",  "2018-03-01",  ["tag","date"]),
    ("events/2018/05_egypt/README.md",                                  "egypt",                          ["event"],       "2018-05-01",  "2018-05-01",  ["tag","date"]),
    ("events/2018/05_gpn18/README.md",                                  "gpn18",                          ["event","gpn"], "2018-05-01",  "2018-05-01",  ["tag","date"]),
    ("events/2018/06_windsurf_instructor_course_hulshorst/README.md",   "windsurf-instructor-course",     ["event","windsurf"], "2018-06-01","2018-06-01",["tag","date"]),
    ("events/2018/07_ich_und_wir_projekt/README.md",                    "ich-und-wir-projekt-2018-07",    ["event"],       "2018-07-01",  "2018-07-01",  ["tag","date"]),
    ("events/2018/10_rhodos/README.md",                                 "rhodos",                         ["event"],       "2018-10-01",  "2018-10-01",  ["tag","date"]),
    ("events/2018/12_35c3_leipzig/README.md",                           "35c3",                           ["event","ccc"], "2018-12-27",  "2018-12-27",  ["tag","date"]),
    ("events/2019/05_gpn19_karlsruhe/README.md",                        "gpn19",                          ["event","gpn"], "2019-05-01",  "2019-05-01",  ["tag","date"]),
    ("events/2019/05_jufo_bundeswettbewerb_chemnitz/README.md",         "jufo-bundeswettbewerb-chemnitz", ["event","jufo"],"2019-05-01",  "2019-05-01",  ["tag","date"]),
    ("events/2019/08_cccamp19_mildenberg/README.md",                    "cccamp19",                       ["event","ccc"], "2019-08-01",  "2019-08-01",  ["tag","date"]),
    ("events/2019/11_labortage_bochum/README.md",                       "labortage-2019",                 ["event","ctf"], "2019-11-01",  "2019-11-01",  ["tag","date"]),
    ("events/2019/12_36c3_leipzig/README.md",                           "36c3",                           ["event","ccc"], "2019-12-27",  "2019-12-27",  ["tag","date"]),
    ("events/2019/12_ski_st_anton/README.md",                           "ski-st-anton",                   ["event","ski"], "2019-12-01",  "2019-12-01",  ["tag","date"]),
    ("events/2020/04_hidden_services/README.md",                        "hidden-services-talk",           ["event","talk"],"2020-04-01",  "2020-04-01",  ["tag","date"]),
    ("events/2020/09_push_to_talk/README.md",                           "push-to-talk",                   ["event","talk"],"2020-09-01",  "2020-09-01",  ["tag","date"]),
    ("events/2020/11_labortage_bochum/README.md",                       "labortage-2020",                 ["event","ctf"], "2020-11-01",  "2020-11-01",  ["tag","date"]),
    ("events/2020/12_rc3/README.md",                                    "rc3-2020",                       ["event","ccc"], "2020-12-01",  "2020-12-01",  ["tag","date"]),
    ("events/2021/04_reboot_to_respawn/README.md",                      "reboot-to-respawn",              ["event","talk"],"2021-04-01",  "2021-04-01",  ["tag","date"]),
    ("events/2021/07_wakeboarding_wedau/README.md",                     "wakeboarding-wedau",             ["event","sport"],"2021-07-01", "2021-07-01",  ["tag","date"]),
    ("events/2021/11_labortage_bochum/README.md",                       "labortage-2021",                 ["event","ctf"], "2021-11-01",  "2021-11-01",  ["tag","date"]),
    ("events/2021/12_rc3/README.md",                                    "rc3-2021",                       ["event","ccc"], "2021-12-01",  "2021-12-01",  ["tag","date"]),
    ("events/2022/01-ski-fiss-ladis/README.md",                         "ski-fiss-ladis",                 ["event","ski"], "2022-01-01",  "2022-01-01",  ["tag","date"]),
    ("events/2022/03-04_bouldern_superblock/README.md",                 "bouldern-superblock",            ["event","sport"],"2022-03-04", "2022-03-04",  ["tag","date"]),
    ("events/2022/03-06_alles_ev_foundation/README.md",                 "alles-ev-foundation",            ["event"],       "2022-03-06",  "2022-03-06",  ["tag","date"]),
    ("events/2022/04-03_kart/README.md",                                "kart",                           ["event"],       "2022-04-03",  "2022-04-03",  ["tag","date"]),
    ("events/2022/04-27_sushi_maki_maki_cologne/README.md",             "sushi-maki-maki-cologne",        ["event"],       "2022-04-27",  "2022-04-27",  ["tag","date"]),
    ("events/2022/04-28_bountyconedu_madrid/README.md",                 "bountyconedu-madrid",            ["event","ctf"], "2022-04-28",  "2022-04-28",  ["tag","date"]),
    ("events/2022/05-19-gpn20-karlsruhe/README.md",                     "gpn20",                          ["event","gpn"], "2022-05-19",  "2022-05-19",  ["tag","date"]),
    ("events/2022/05-20-heidelberg/README.md",                          "heidelberg-2022",                ["event"],       "2022-05-20",  "2022-05-20",  ["tag","date"]),
    ("events/2022/05-28-chaotikum-lübeck/README.md",                    "chaotikum-lubeck",               ["event"],       "2022-05-28",  "2022-05-28",  ["tag","date"]),
    ("events/2022/05-28-jufo-bundeswettbewerb-lübeck/README.md",        "jufo-bundeswettbewerb-lubeck",   ["event","jufo"],"2022-05-28",  "2022-05-28",  ["tag","date"]),
    ("events/2022/06-02-emf-camp-eastnor/README.md",                    "emf-camp-eastnor",               ["event"],       "2022-06-02",  "2022-06-02",  ["tag","date"]),
    ("events/2022/06-11-docklands-münster/README.md",                   "docklands-munster",              ["event"],       "2022-06-11",  "2022-06-11",  ["tag","date"]),
    ("events/2022/06-11-warpzone-münster/README.md",                    "warpzone-munster",               ["event"],       "2022-06-11",  "2022-06-11",  ["tag","date"]),
    ("events/2022/06-29-troopers-heidelberg/README.md",                 "troopers-heidelberg",            ["event","ctf"], "2022-06-29",  "2022-06-29",  ["tag","date"]),
    ("events/2022/07-22-mch-zeewolde/README.md",                        "mch-zeewolde",                   ["event"],       "2022-07-22",  "2022-07-22",  ["tag","date"]),
    ("events/2022/08-01-windsurf-portugal-viana-do-castelo/README.md",  "windsurf-portugal",              ["event","windsurf"],"2022-08-01","2022-08-01", ["tag","date"]),
    ("events/2022/08-08-blackhat-las-vegas/README.md",                  "blackhat-2022",                  ["event","ctf"], "2022-08-08",  "2022-08-08",  ["tag","date"]),
    ("events/2022/08-11-defcon-30-las-vegas/README.md",                 "defcon30",                       ["event","ctf"], "2022-08-11",  "2022-08-11",  ["tag","date"]),
    ("events/2022/11-11-labortage-bochum/README.md",                    "labortage-2022",                 ["event","ctf"], "2022-11-11",  "2022-11-11",  ["tag","date"]),
    ("events/2022/12-01-lanzarote-fuerteventura/README.md",             "lanzarote-fuerteventura",        ["event"],       "2022-12-01",  "2022-12-01",  ["tag","date"]),
    ("events/2022/12-27-HIP-Berlin/README.md",                          "hip-berlin",                     ["event","ccc"], "2022-12-27",  "2022-12-27",  ["tag","date"]),
    ("events/2023/01-munich/README.md",                                 "munich-2023",                    ["event"],       "2023-01-01",  "2023-01-01",  ["tag","date"]),
    ("events/2023/02-cccactfebuar-aachen/README.md",                    "cccactfebuar-aachen",            ["event","ctf"], "2023-02-01",  "2023-02-01",  ["tag","date"]),
    ("events/2023/02-fosdem-brussels/README.md",                        "fosdem-2023",                    ["event"],       "2023-02-01",  "2023-02-01",  ["tag","date"]),
    ("events/2023/03-eatin-snacks-and-getting-flags-duisburg/README.md","eatin-snacks-duisburg",          ["event","ctf"], "2023-03-01",  "2023-03-01",  ["tag","date"]),
    ("events/2023/03-geekend-berlin/README.md",                         "geekend-berlin-2023",            ["event"],       "2023-03-01",  "2023-03-01",  ["tag","date"]),
    ("events/2023/03-tag-des-offenen-hackspaces-düsseldorf/README.md",  "tag-des-offenen-hackspaces",     ["event"],       "2023-03-01",  "2023-03-01",  ["tag","date"]),
    ("events/2023/04-easterhegg/README.md",                             "easterhegg-2023",                ["event","ccc"], "2023-04-01",  "2023-04-01",  ["tag","date"]),
    ("events/2023/04-newline-gent/README.md",                           "newline-gent",                   ["event"],       "2023-04-01",  "2023-04-01",  ["tag","date"]),
    ("events/2023/04-plaidctf/README.md",                               "plaidctf-2023",                  ["event","ctf"], "2023-04-01",  "2023-04-01",  ["tag","date"]),
    ("events/2023/05-defi-wind/README.md",                              "defi-wind",                      ["event","windsurf"],"2023-05-01","2023-05-01", ["tag","date"]),
    ("events/2023/06-boulder-superblock-düsseldorf/README.md",          "boulder-superblock-2023",        ["event","sport"],"2023-06-01", "2023-06-01",  ["tag","date"]),
    ("events/2023/06-bsides-indor-ctf-aachen/README.md",                "bsides-indor-ctf",               ["event","ctf"], "2023-06-01",  "2023-06-01",  ["tag","date"]),
    ("events/2023/06-google-ctf/README.md",                             "google-ctf-2023",                ["event","ctf"], "2023-06-01",  "2023-06-01",  ["tag","date"]),
    ("events/2023/06-GPN/README.md",                                    "gpn23",                          ["event","gpn"], "2023-06-01",  "2023-06-01",  ["tag","date"]),
    ("events/2023/06-p4ctf-finals-katowice/README.md",                  "p4ctf-finals",                   ["event","ctf"], "2023-06-01",  "2023-06-01",  ["tag","date"]),
    ("events/2023/07-berlin-tour/README.md",                            "berlin-tour-2023",               ["event"],       "2023-07-01",  "2023-07-01",  ["tag","date"]),
    ("events/2023/07-birthday/README.md",                               "birthday-2023",                  ["event"],       "2023-07-01",  "2023-07-01",  ["tag","date"]),
    ("events/2023/07-chaos-jetzt-geekend-leipzig/README.md",            "chaos-jetzt-geekend-leipzig",    ["event"],       "2023-07-01",  "2023-07-01",  ["tag","date"]),
    ("events/2023/07-milliways-storage-day/README.md",                  "milliways-storage-day",          ["event"],       "2023-07-01",  "2023-07-01",  ["tag","date"]),
    ("events/2023/07-new-york/README.md",                               "new-york-2023",                  ["event"],       "2023-07-01",  "2023-07-01",  ["tag","date"]),
    ("events/2023/08-cccamp/README.md",                                 "cccamp23",                       ["event","ccc"], "2023-08-01",  "2023-08-01",  ["tag","date"]),
    ("events/2023/08-defcon/README.md",                                 "defcon-2023",                    ["event","ctf"], "2023-08-01",  "2023-08-01",  ["tag","date"]),
    ("events/2023/09-balccon-novi-sad/README.md",                       "balccon",                        ["event"],       "2023-09-01",  "2023-09-01",  ["tag","date"]),
    ("events/2023/09-mrmcd-darmstadt/README.md",                        "mrmcd-2023",                     ["event"],       "2023-09-01",  "2023-09-01",  ["tag","date"]),
    ("events/2023/09-regiowochenende/README.md",                        "regiowochenende-2023",           ["event"],       "2023-09-01",  "2023-09-01",  ["tag","date"]),
    ("events/2023/10-ctf-weekend-cccac-aachen/README.md",               "ctf-weekend-aachen",             ["event","ctf"], "2023-10-01",  "2023-10-01",  ["tag","date"]),
    ("events/2023/10-halloween-ctf-bonn/README.md",                     "halloween-ctf-bonn",             ["event","ctf"], "2023-10-01",  "2023-10-01",  ["tag","date"]),
    ("events/2023/11-labortage-bochum/README.md",                       "labortage-2023",                 ["event","ctf"], "2023-11-01",  "2023-11-01",  ["tag","date"]),
    ("events/2023/12-37c3/README.md",                                   "37c3",                           ["event","ccc"], "2023-12-27",  "2023-12-27",  ["tag","date"]),
    ("events/2023/12-ski-ishgl/README.md",                              "ski-ishgl",                      ["event","ski"], "2023-12-01",  "2023-12-01",  ["tag","date"]),
    ("events/2024/02-chaos-jetzt-geekend-bochum/README.md",             "chaos-jetzt-geekend-bochum",     ["event"],       "2024-02-01",  "2024-02-01",  ["tag","date"]),
    ("events/2024/05-koblenz-freiburg-by-bike/README.md",               "koblenz-freiburg-by-bike",       ["event","sport"],"2024-05-01", "2024-05-01",  ["tag","date"]),
    ("events/2024/06-EMFCAMP/README.md",                                "emfcamp-2024",                   ["event"],       "2024-06-01",  "2024-06-01",  ["tag","date"]),
    ("events/2024/06-toorcamp/README.md",                               "toorcamp",                       ["event"],       "2024-06-01",  "2024-06-01",  ["tag","date"]),
    ("events/2024/09-hacks-on-the-beach-flensburg/README.md",           "hacks-on-the-beach",             ["event","ctf"], "2024-09-01",  "2024-09-01",  ["tag","date"]),
    ("events/2024/09-jetzt6-chaos-jetzt-geekend-wien/README.md",        "chaos-jetzt-geekend-wien",       ["event"],       "2024-09-01",  "2024-09-01",  ["tag","date"]),
    ("events/2024/10-ccc-regiowochenende-mühldorf-am-inn/README.md",    "ccc-regiowochenende-muhldorf",   ["event"],       "2024-10-01",  "2024-10-01",  ["tag","date"]),
    ("events/2024/10-mrmcd-darmstadt/README.md",                        "mrmcd-2024",                     ["event"],       "2024-10-01",  "2024-10-01",  ["tag","date"]),
    ("events/2024/11-asia/README.md",                                   "asia-2024",                      ["event"],       "2024-11-01",  "2024-11-01",  ["tag","date"]),
    ("events/2024/11-r2con-barcelona/README.md",                        "r2con-barcelona",                ["event","ctf"], "2024-11-01",  "2024-11-01",  ["tag","date"]),
    ("events/2024/12-38c3-Hamburg/README.md",                           "38c3",                           ["event","ccc"], "2024-12-27",  "2024-12-27",  ["tag","date"]),
    ("events/2024/12-tenerife/README.md",                               "tenerife-2024",                  ["event"],       "2024-12-01",  "2024-12-01",  ["tag","date"]),
    ("events/2025/02-28-hackimpott/README.md",                          "hackimpott",                     ["event","ctf"], "2025-02-28",  "2025-02-28",  ["tag","date"]),
    ("events/2025/04-easterhegg/README.md",                             "easterhegg-2025",                ["event","ccc"], "2025-04-01",  "2025-04-01",  ["tag","date"]),
    ("events/2025/05-tenerife/README.md",                               "tenerife-2025-05",               ["event"],       "2025-05-01",  "2025-05-01",  ["tag","date"]),
    ("events/2025/06-DHM/README.md",                                    "dhm",                            ["event","windsurf"],"2025-06-01","2025-06-01", ["tag","date"]),
    ("events/2025/06-gpn/README.md",                                    "gpn25",                          ["event","gpn"], "2025-06-01",  "2025-06-01",  ["tag","date"]),
    ("events/2025/08-why/README.md",                                    "why25",                          ["event"],       "2025-08-01",  "2025-08-01",  ["tag","date"]),
    ("events/2025/09-asia/README.md",                                   "asia-2025",                      ["event"],       "2025-09-01",  "2025-09-01",  ["tag","date"]),
    ("events/2025/09-tenerife/README.md",                               "tenerife-2025-09",               ["event"],       "2025-09-01",  "2025-09-01",  ["tag","date"]),
    ("events/2025/09-veluvemeer/README.md",                             "veluvemeer",                     ["event"],       "2025-09-01",  "2025-09-01",  ["tag","date"]),
    ("events/2025/12-39c3/README.md",                                   "39c3",                           ["event","ccc"], "2025-12-27",  "2025-12-27",  ["tag","date"]),
    ("events/2026/03-arlberg/README.md",                                "arlberg",                        ["event","ski"], "2026-03-01",  "2026-03-01",  ["tag","date"]),
    ("events/2026/06-GPN/README.md",                                    "gpn26",                          ["event","gpn"], "2026-06-01",  "2026-06-01",  ["tag","date"]),

    # ── CTF resources ────────────────────────────────────────────────────
    ("ctf/resources/assembly-basics/README.md",      "assembly-basics",      ["ctf","resource"],  "2022-01-01", None, ["tag"]),
    ("ctf/resources/format-strings/README.md",       "format-strings",       ["ctf","resource"],  "2022-01-01", None, ["tag"]),
    ("ctf/resources/fuzzing/README.md",              "fuzzing",              ["ctf","resource"],  "2022-01-01", None, ["tag"]),
    ("ctf/resources/heap/README.md",                 "heap",                 ["ctf","resource"],  "2022-01-01", None, ["tag"]),
    ("ctf/resources/integer-overflow/README.md",     "integer-overflow",     ["ctf","resource"],  "2022-01-01", None, ["tag"]),
    ("ctf/resources/jump-tables/README.md",          "jump-tables",          ["ctf","resource"],  "2022-01-01", None, ["tag"]),
    ("ctf/resources/kernel/README.md",               "kernel",               ["ctf","resource"],  "2022-01-01", None, ["tag"]),
    ("ctf/resources/mitigations/README.md",          "mitigations",          ["ctf","resource"],  "2022-01-01", None, ["tag"]),
    ("ctf/resources/overflow/README.md",             "overflow",             ["ctf","resource"],  "2022-01-01", None, ["tag"]),
    ("ctf/resources/rop/README.md",                  "rop",                  ["ctf","resource"],  "2022-01-01", None, ["tag"]),
    ("ctf/resources/shellcode/README.md",            "shellcode",            ["ctf","resource"],  "2022-01-01", None, ["tag"]),
    ("ctf/resources/symbolic-execution/README.md",   "symbolic-execution",   ["ctf","resource"],  "2022-01-01", None, ["tag"]),

    # ── CTF teams ────────────────────────────────────────────────────────
    ("ctf/teams/ALLES/README.md",          "alles",            ["ctf","team"],  "2022-01-01", None, ["tag"]),
    ("ctf/teams/dussec/README.md",         "dussec",           ["ctf","team"],  "2022-01-01", None, ["tag"]),
    ("ctf/teams/flexerilla/README.md",     "flexerilla",       ["ctf","team"],  "2022-01-01", None, ["tag"]),
    ("ctf/teams/hanemile/README.md",       "ctf-hanemile",     ["ctf","team"],  "2022-01-01", None, ["tag"]),
    ("ctf/teams/kuchenblechmafia/README.md","kuchenblechmafia",["ctf","team"],  "2022-01-01", None, ["tag"]),

    # ── CTF writeups ─────────────────────────────────────────────────────
    ("ctf/writeups/2019/dc2019q/cant_even_unplug_it/README.md", "writeup-cant-even-unplug-it", ["ctf","writeup"],  "2019-01-01", None, ["tag","published"]),
    ("ctf/writeups/2019/dc2019q/know_your_mem/README.md",       "writeup-know-your-mem",       ["ctf","writeup"],  "2019-01-01", None, ["tag","published"]),
    ("ctf/writeups/2019/dc2019q/welcome-to-the-game/README.md", "writeup-welcome-to-the-game", ["ctf","writeup"],  "2019-01-01", None, ["tag","published"]),
    ("ctf/writeups/2020/hacklu/confessions/README.md",          "writeup-confessions",         ["ctf","writeup"],  "2020-10-01", None, ["tag","published"]),
    ("ctf/writeups/2020/nahamconCTF/complete-flag-leak/README.md","writeup-complete-flag-leak", ["ctf","writeup"],  "2020-06-01", None, ["tag","published"]),
    ("ctf/writeups/2020/redpwnCTF/pseudo-key/README.md",        "writeup-pseudo-key",          ["ctf","writeup"],  "2020-06-01", None, ["tag","published"]),
    ("ctf/writeups/2021/labortage-ctf/licence-one/README.md",   "writeup-licence-one",         ["ctf","writeup"],  "2021-11-01", None, ["tag","published"]),
    ("ctf/writeups/pwnable.kr/bof/README.md",                   "writeup-bof",                 ["ctf","writeup"],  "2020-01-01", None, ["tag","published"]),
    ("ctf/writeups/pwnable.kr/collision/README.md",             "writeup-collision",           ["ctf","writeup"],  "2020-01-01", None, ["tag","published"]),
    ("ctf/writeups/pwnable.kr/fd/README.md",                    "writeup-fd",                  ["ctf","writeup"],  "2020-01-01", None, ["tag","published"]),
    ("ctf/writeups/pwnable.kr/flag/README.md",                  "writeup-flag",                ["ctf","writeup"],  "2020-01-01", None, ["tag","published"]),

    # ── CTF hosted events ────────────────────────────────────────────────
    ("ctf/hosted-events/2019-dorfCTF/README.md",      "dorfctf",          ["ctf","event"],  "2019-01-01", "2019-01-01", ["tag","date"]),
    ("ctf/hosted-events/2020-labortageCTF/README.md", "labortagectf-2020",["ctf","event"],  "2020-11-01", "2020-11-01", ["tag","date"]),
    ("ctf/hosted-events/2021-labortageCTF/README.md", "labortagectf-2021",["ctf","event"],  "2021-11-01", "2021-11-01", ["tag","date"]),

    # ── Projects ─────────────────────────────────────────────────────────
    ("projects/astrophotography/README.md",           "astrophotography",     ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/BMC/README.md",                        "bmc",                  ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/boat/README.md",                       "boat",                 ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/books/README.md",                      "books",                ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/casio/README.md",                      "casio",                ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/chaosdorf/README.md",                  "chaosdorf",            ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/charon/README.md",                     "charon",               ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/circus/README.md",                     "circus",               ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/cocktails/README.md",                  "cocktails",            ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/cocktails/apple-paloma/README.md",     "apple-paloma",         ["project","cocktail"],  "2022-01-01", None, ["tag"]),
    ("projects/cocktails/capgemini/README.md",        "capgemini-cocktail",   ["project","cocktail"],  "2022-01-01", None, ["tag"]),
    ("projects/conversation/README.md",               "conversation",         ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/drone/README.md",                      "drone",                ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/emu/README.md",                        "emu",                  ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/ergomechkeyboards/README.md",          "ergomechkeyboards",    ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/ergomechkeyboards/corne/README.md",    "corne",                ["project","keyboard"],  "2022-01-01", None, ["tag"]),
    ("projects/ergomechkeyboards/ferris-sweep/README.md","ferris-sweep",      ["project","keyboard"],  "2022-01-01", None, ["tag"]),
    ("projects/ergomechkeyboards/skeletyl/README.md", "skeletyl",             ["project","keyboard"],  "2022-01-01", None, ["tag"]),
    ("projects/games/0h-gamejam-2019/README.md",      "0h-gamejam-2019",      ["project","game"],  "2019-01-01", None, ["tag"]),
    ("projects/giff/README.md",                       "giff",                 ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/glitchart/README.md",                  "glitchart",            ["project","art"],  "2022-01-01", None, ["tag"]),
    ("projects/gnirbew/README.md",                    "gnirbew",              ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/hefe3/README.md",                      "hefe3",                ["project","nix"],  "2022-01-01", None, ["tag"]),
    ("projects/honeysuite/README.md",                 "honeysuite",           ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/http-servers/faila/README.md",         "faila",                ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/http-servers/graph-clicker/README.md", "graph-clicker",        ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/http-servers/metrics-bundler/README.md","metrics-bundler",     ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/http-servers/randomhttp/README.md",    "randomhttp",           ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/http-servers/redir/README.md",         "redir",                ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/http-servers/reqlog/README.md",        "reqlog",               ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/jufo/README.md",                       "jufo",                 ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/jufo/2017-satellite-collisions/README.md","jufo-satellite-collisions",["project","jufo"],"2017-01-01",None,["tag"]),
    ("projects/jufo/2019-galaxy-simulation/README.md","jufo-galaxy-simulation",["project","jufo"],"2019-01-01",None,["tag"]),
    ("projects/led-cube/README.md",                   "led-cube",             ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/matrix/matrix-sdk/README.md",          "matrix-sdk",           ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/matrix/matrix-weather-bot/README.md",  "matrix-weather-bot",   ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/megadesk/README.md",                   "megadesk",             ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/miboma/README.md",                     "miboma",               ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/mobesi/README.md",                     "mobesi",               ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/monopokerly/README.md",                "monopokerly",          ["project","game"],  "2022-01-01", None, ["tag"]),
    ("projects/paged-out/README.md",                  "paged-out",            ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/photography/README.md",                "photography",          ["project","photos"],  "2022-01-01", None, ["tag"]),
    ("projects/pixeltsunami/README.md",               "pixeltsunami",         ["project","art"],  "2022-01-01", None, ["tag"]),
    ("projects/stdin-to-tcp/README.md",               "stdin-to-tcp",         ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/toki-pona/README.md",                  "toki-pona",            ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/trike/README.md",                      "trike",                ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/vokobe/README.md",                     "vokobe",               ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/xilero/README.md",                     "xilero",               ["project"],  "2022-01-01", None, ["tag"]),
    ("projects/yonilu/README.md",                     "yonilu",               ["project"],  "2022-01-01", None, ["tag"]),

    # ── Sport ────────────────────────────────────────────────────────────
    ("sport/bike/README.md",                     "bike",                 ["sport"],          "2022-01-01", None, ["tag"]),
    ("sport/bike/pickenflick/README.md",         "pickenflick",          ["sport","bike"],   "2022-01-01", None, ["tag"]),
    ("sport/bike/stumpjumper/README.md",         "stumpjumper",          ["sport","bike"],   "2022-01-01", None, ["tag"]),
    ("sport/bike/trifold/README.md",             "trifold",              ["sport","bike"],   "2022-01-01", None, ["tag"]),
    ("sport/billiard/README.md",                 "billiard",             ["sport"],          "2022-01-01", None, ["tag"]),
    ("sport/boulder/README.md",                  "boulder",              ["sport"],          "2022-01-01", None, ["tag"]),
    ("sport/dive/README.md",                     "dive",                 ["sport"],          "2022-01-01", None, ["tag"]),
    ("sport/run/README.md",                      "run",                  ["sport"],          "2022-01-01", None, ["tag"]),
    ("sport/sail/README.md",                     "sail",                 ["sport"],          "2022-01-01", None, ["tag"]),
    ("sport/sail/2026-07-Flensburg/README.md",   "sailing-flensburg-2026",["sport","sail","event"],"2026-07-01","2026-07-01",["tag","date"]),
    ("sport/ski/README.md",                      "ski",                  ["sport"],          "2022-01-01", None, ["tag"]),
    ("sport/swim/README.md",                     "swim",                 ["sport"],          "2022-01-01", None, ["tag"]),
    ("sport/wakeboarding/README.md",             "wakeboarding",         ["sport"],          "2022-01-01", None, ["tag"]),
    ("sport/windsurf/README.md",                 "windsurf",             ["sport"],          "2022-01-01", None, ["tag"]),
    ("sport/windsurf/knowledge/fin/README.md",   "windsurf-fin",         ["sport","windsurf"],"2022-01-01",None, ["tag"]),
    ("sport/windsurf/knowledge/mast/README.md",  "windsurf-mast",        ["sport","windsurf"],"2022-01-01",None, ["tag"]),
    ("sport/windsurf/knowledge/sail/README.md",  "windsurf-sail",        ["sport","windsurf"],"2022-01-01",None, ["tag"]),

    # ── Talks ────────────────────────────────────────────────────────────
    ("talks/2017/2017-10-13-satellite-collisions-galaxy-visualizations/README.md","talk-satellite-collisions",["talk"],"2017-10-13","2017-10-13",["tag","date"]),
    ("talks/2019/2019-04-24-ctf-vorstellung/README.md",     "talk-ctf-vorstellung",   ["talk"], "2019-04-24","2019-04-24",["tag","date"]),
    ("talks/2019/2019-06-07-honeypot-escalation/README.md", "talk-honeypot-escalation",["talk"],"2019-06-07","2019-06-07",["tag","date"]),
    ("talks/2019/2019-07-26-awesome-pairprogramming/README.md","talk-pairprogramming", ["talk"],"2019-07-26","2019-07-26",["tag","date"]),
    ("talks/2019/2019-08-16-paged-out/README.md",           "talk-paged-out",         ["talk"], "2019-08-16","2019-08-16",["tag","date"]),
    ("talks/2019/2019-12-29-ctf-in-a-box/README.md",        "talk-ctf-in-a-box",      ["talk"], "2019-12-29","2019-12-29",["tag","date"]),
    ("talks/2020/2020-02-28-r2wars-teaser/README.md",       "talk-r2wars-teaser",     ["talk"], "2020-02-28","2020-02-28",["tag","date"]),
    ("talks/2021/2021-04-03-betreutes-hacken/README.md",    "talk-betreutes-hacken",  ["talk"], "2021-04-03","2021-04-03",["tag","date"]),

    # ── Workshops ────────────────────────────────────────────────────────
    ("workshops/2019/09-28-blender-2-8-chaosdorf/README.md",          "workshop-blender-28",            ["workshop"],   "2019-09-28","2019-09-28",["tag","date"]),
    ("workshops/2021/12-14-ctf/README.md",                             "workshop-ctf-2021-12",           ["workshop","ctf"],"2021-12-14","2021-12-14",["tag","date"]),
    ("workshops/2021/12-28-orca/README.md",                            "workshop-orca",                  ["workshop"],   "2021-12-28","2021-12-28",["tag","date"]),
    ("workshops/2022/ctf-foo/01-15-ctf/README.md",                     "ctf-foo-01-15",                  ["workshop","ctf"],"2022-01-15","2022-01-15",["tag","date"]),
    ("workshops/2022/ctf-foo/02-05-ctf/README.md",                     "ctf-foo-02-05",                  ["workshop","ctf"],"2022-02-05","2022-02-05",["tag","date"]),
    ("workshops/2022/ctf-foo/03-05-ctf-foo-assembly-basics/README.md", "ctf-foo-assembly-basics",        ["workshop","ctf"],"2022-03-05","2022-03-05",["tag","date"]),
    ("workshops/2022/ctf-foo/03-19-ctf-foo-linux/README.md",           "ctf-foo-linux",                  ["workshop","ctf"],"2022-03-19","2022-03-19",["tag","date"]),
    ("workshops/2022/ctf-foo/04-02-ctf-foo-buffer-overflow/README.md", "ctf-foo-buffer-overflow",        ["workshop","ctf"],"2022-04-02","2022-04-02",["tag","date"]),
    ("workshops/2022/ctf-foo/04-16-ctf-foo-shellcode/README.md",       "ctf-foo-shellcode",              ["workshop","ctf"],"2022-04-16","2022-04-16",["tag","date"]),
    ("workshops/2022/ctf-foo/04-30-ctf-foo-rop/README.md",             "ctf-foo-rop",                    ["workshop","ctf"],"2022-04-30","2022-04-30",["tag","date"]),
    ("workshops/2022/ctf-foo/05-14-ctf-foo-infoleaks/README.md",       "ctf-foo-infoleaks",              ["workshop","ctf"],"2022-05-14","2022-05-14",["tag","date"]),
    ("workshops/2022/ctf-foo/05-28-ctf-foo-mitigations/README.md",     "ctf-foo-mitigations",            ["workshop","ctf"],"2022-05-28","2022-05-28",["tag","date"]),
    ("workshops/2022/ctf-foo/06-11-ctf-foo-reversing/README.md",       "ctf-foo-reversing",              ["workshop","ctf"],"2022-06-11","2022-06-11",["tag","date"]),
    ("workshops/2022/ctf-foo/06-25-ctf-foo-heap-basics/README.md",     "ctf-foo-heap-basics",            ["workshop","ctf"],"2022-06-25","2022-06-25",["tag","date"]),
    ("workshops/2022/ctf-foo/07-09-ctf-foo-heap-techniques/README.md", "ctf-foo-heap-techniques",        ["workshop","ctf"],"2022-07-09","2022-07-09",["tag","date"]),
    ("workshops/2022/ctf-foo/07-23-ctf-foo-race-conditions/README.md", "ctf-foo-race-conditions",        ["workshop","ctf"],"2022-07-23","2022-07-23",["tag","date"]),
    ("workshops/2022/ctf-foo/08-06-ctf-foo-fuzzing/README.md",         "ctf-foo-fuzzing",                ["workshop","ctf"],"2022-08-06","2022-08-06",["tag","date"]),
    ("workshops/2022/ctf-foo/08-20-ctf-foo-kernel-security/README.md", "ctf-foo-kernel-security",        ["workshop","ctf"],"2022-08-20","2022-08-20",["tag","date"]),
    ("workshops/2022/ctf-foo/09-03-ctf-foo-symbolic-execution/README.md","ctf-foo-symbolic-execution",   ["workshop","ctf"],"2022-09-03","2022-09-03",["tag","date"]),
    ("workshops/2022/ctf-foo/09-17-ctf-foo-automated-program-analysis/README.md","ctf-foo-automated-analysis",["workshop","ctf"],"2022-09-17","2022-09-17",["tag","date"]),
    ("workshops/2023/README.md",                                       "workshops-2023",                 ["workshop"],   "2023-01-01", None,         []),

    # ── Publications ─────────────────────────────────────────────────────
    ("publications/2018/glitch-gallery/README.md",                                                    "glitch-gallery",         ["publication"],  "2018-01-01","2018-01-01",["tag","date"]),
    ("publications/2019/Galaxy-Simluation/README.md",                                                 "galaxy-simulation",      ["publication"],  "2019-01-01","2019-01-01",["tag","date"]),
    ("publications/2020/Accelerating-simulations-by-clustering-bodies-using-the-Barnes-Hut-algorithm/README.md","accelerating-simulations",["publication"],"2020-01-01","2020-01-01",["tag","date"]),

    # ── Files / misc ─────────────────────────────────────────────────────
    ("files/ctf_beginner_pres/README.md",   "ctf-beginner-pres",  ["files","ctf"],   "2022-01-01", None, ["tag"]),
    ("files/postgres-docker/README.md",     "postgres-docker",    ["files"],         "2022-01-01", None, ["tag"]),
    ("files/pwn-setup/README.md",           "pwn-setup",          ["files","ctf"],   "2022-01-01", None, ["tag"]),
]

# Pages already fully migrated (skip writing but mark done in checklist)
ALREADY_DONE = {
    "about", "blog", "ctf", "index", "irc", "offline-rust-stdlib-docs",
    "projects", "publications", "r2wars", "sport", "talks", "workshops",
    "34c3", "35c3", "lausanne-ski-2017",
}


def make_meta(tags, published, event_date, info_keys, modified=TODAY):
    tag_str = " ".join(f'"{t}"' for t in tags)
    lines = [f"(meta"]
    if tags:
        lines.append(f'  (tag {tag_str})')
    lines.append(f'  (published "{published}")')
    lines.append(f'  (modified "{modified}")')
    if event_date:
        lines.append(f'  (date "{event_date}")')
    lines.append(f'  (author "Emile")')
    if info_keys:
        info_str = " ".join(f'"{k}"' for k in info_keys)
        lines.append(f'  (info {info_str})')
    lines.append(")")
    return "\n".join(lines)


def old_url(rel_path):
    """Return the old URL for a given rel_path (e.g. blog/2020/foo/README.md → /blog/2020/foo/)"""
    parts = Path(rel_path).parts
    if parts[-1] == "README.md":
        dir_parts = parts[:-1]
    else:
        dir_parts = parts
    if not dir_parts:
        return "/"
    return "/" + "/".join(dir_parts) + "/"


def migrate():
    created, skipped, already = 0, 0, 0

    redirect_lines = []
    checklist_sections = {}

    for (rel, name, tags, published, event_date, info_keys) in PAGES:
        src = OLD / rel
        dst = NEW / f"{name}.md"
        url_old = old_url(rel)
        url_new = f"/{name}"

        # section for checklist
        section = rel.split("/")[0] if "/" in rel else "root"
        if section not in checklist_sections:
            checklist_sections[section] = []

        # determine if already done
        done = name in ALREADY_DONE or dst.exists()

        if done:
            checklist_sections[section].append((True, rel, name, url_old, url_new))
            already += 1
        elif not src.exists():
            checklist_sections[section].append((False, rel, name, url_old, url_new))
            skipped += 1
            print(f"  MISSING  {rel}")
        else:
            content = src.read_text(encoding="utf-8", errors="replace")
            meta = make_meta(tags, published, event_date, info_keys)
            new_content = meta + "\n\n" + content
            dst.write_text(new_content, encoding="utf-8")
            checklist_sections[section].append((True, rel, name, url_old, url_new))
            created += 1
            print(f"  created  {name}.md")

        # redirect (old URL → new URL), skip if they're the same
        if url_old.rstrip("/") != url_new:
            redirect_lines.append(f'location = {url_old} {{ return 301 {url_new}; }}')
            # also without trailing slash variant
            bare = url_old.rstrip("/")
            if bare and bare != url_old and bare != url_new:
                redirect_lines.append(f'location = {bare} {{ return 301 {url_new}; }}')

    print(f"\nDone: {created} created, {already} already done, {skipped} source missing")

    # Write nginx redirects
    redir_path = Path(__file__).parent / "nginx" / "redirects.conf"
    redir_path.write_text(
        "# Auto-generated by migrate.py — old emile.space tree URLs → new flat URLs\n"
        "# Include this inside the emile.space server{} block.\n\n"
        + "\n".join(redirect_lines) + "\n",
        encoding="utf-8"
    )
    print(f"Wrote {redir_path}")

    # Write checklist
    cl_path = Path(__file__).parent / "MIGRATION.md"
    lines = ["# Migration checklist", "",
             "Old tree path → new flat name. Checked = file exists in `v2/input/`.", ""]
    section_order = ["root","about","blog","events","ctf","projects","sport","talks","workshops","publications","files","irc","search"]
    all_sections = section_order + [s for s in checklist_sections if s not in section_order]
    for sec in all_sections:
        if sec not in checklist_sections:
            continue
        entries = checklist_sections[sec]
        lines.append(f"## {sec}")
        lines.append("")
        for (done, rel, name, url_old, url_new) in entries:
            box = "x" if done else " "
            lines.append(f"- [{box}] `{rel}` → [`{name}`]({url_new})")
        lines.append("")
    cl_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {cl_path}")


if __name__ == "__main__":
    migrate()
