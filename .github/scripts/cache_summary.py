#!/usr/bin/env python3
"""Parse application.properties for cache configuration and write a GitHub Step Summary.

Usage: python3 cache_summary.py [application.properties]
"""
import os, re, sys

CACHE_KEYS = {
    "spring.cache.type":          ("Cache provider",    "ConcurrentMap (default)"),
    "spring.cache.cache-names":   ("Cache regions",     "(none configured)"),
    "spring.cache.caffeine.spec": ("Caffeine spec",     "(default)"),
}

ANNOTATED_METHODS = [
    ("pets",        "findAllPets()",               "@Cacheable",   "Collection-level read"),
    ("pets",        "savePet() / deletePet()",     "@CacheEvict",  "beforeInvocation=true, allEntries=true"),
    ("visits",      "findAllVisits()",             "@Cacheable",   "Collection-level read"),
    ("visits",      "findVisitsByPetId(petId)",    "@Cacheable",   "key='byPet_'+petId"),
    ("visits",      "saveVisit() / deleteVisit()", "@CacheEvict",  "beforeInvocation=true, allEntries=true"),
    ("vets",        "findAllVets() / findVets()",  "@Cacheable",   "Collection-level read"),
    ("vets",        "saveVet() / deleteVet()",     "@CacheEvict",  "beforeInvocation=true, allEntries=true"),
    ("owners",      "findAllOwners()",             "@Cacheable",   "Collection-level read"),
    ("owners",      "findOwnerByLastName(name)",   "@Cacheable",   "key='byLastName_'+lastName"),
    ("owners",      "saveOwner() / deleteOwner()", "@CacheEvict",  "beforeInvocation=true, allEntries=true"),
    ("petTypes",    "findAllPetTypes() / findPetTypes()", "@Cacheable", "Collection-level read"),
    ("petTypes",    "savePetType() / deletePetType()",    "@CacheEvict", "beforeInvocation=true, allEntries=true"),
    ("specialties", "findAllSpecialties()",        "@Cacheable",   "Collection-level read"),
    ("specialties", "saveSpecialty() / deleteSpecialty()", "@CacheEvict", "beforeInvocation=true, allEntries=true"),
]


def parse_properties(path):
    props = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, _, v = line.partition("=")
                    props[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return props


def main():
    props_file = sys.argv[1] if len(sys.argv) > 1 else "src/main/resources/application.properties"
    props = parse_properties(props_file)

    # --- Configuration section ---
    lines = [
        "## Caching Configuration",
        "",
        "| Property | Value |",
        "|---|---|",
    ]
    for key, (label, default) in CACHE_KEYS.items():
        value = props.get(key, default)
        lines.append(f"| {label} | `{value}` |")

    # Parse Caffeine spec into human-readable fields
    spec = props.get("spring.cache.caffeine.spec", "")
    if spec:
        lines += ["", "### Caffeine spec breakdown", "", "| Parameter | Value |", "|---|---|"]
        for part in spec.split(","):
            part = part.strip()
            m = re.match(r"(\w+)=(.+)", part)
            if m:
                lines.append(f"| `{m.group(1)}` | {m.group(2)} |")
            else:
                lines.append(f"| `{part}` | (flag) |")

    # --- Annotated methods section ---
    lines += [
        "",
        "### Cached Service Methods (`ClinicServiceImpl`)",
        "",
        "| Cache | Method | Annotation | Notes |",
        "|---|---|---|---|",
    ]
    for cache, method, annotation, notes in ANNOTATED_METHODS:
        lines.append(f"| `{cache}` | `{method}` | `{annotation}` | {notes} |")

    lines += [
        "",
        "> **Eviction strategy:** `@CacheEvict(beforeInvocation = true)` is used on all writes "
        "so subsequent reads within the same transaction always go to the database.",
        "> **Single-entity by-ID lookups** are intentionally not cached to prevent stale reads "
        "after `@Transactional` rollbacks.",
        "",
    ]

    sep = chr(10)
    body = sep.join(lines) + sep
    sf = os.environ.get("GITHUB_STEP_SUMMARY")
    if sf:
        with open(sf, "a") as fh:
            fh.write(body)
    else:
        print(body)


if __name__ == "__main__":
    main()
