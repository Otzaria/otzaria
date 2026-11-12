#!/usr/bin/env python3
"""Plot every measured long-book latency, keeping process groups separate."""

import argparse
import hashlib
import json
from pathlib import Path
from statistics import median

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.ticker import FuncFormatter, MaxNLocator


def hebrew(text):
    # Only pure Hebrew labels pass here; IDs and numbers remain separate.
    return text[::-1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact_root", type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--design", choices=["whole-pr", "representation-only"], required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.output.with_suffix(".json").exists():
        raise SystemExit("Output already exists")

    root = args.artifact_root
    provenance = json.loads((root / "provenance.json").read_text(encoding="utf-8-sig"))
    assert provenance["candidateSourceCommit"] == args.candidate
    assert provenance["baselineSourceCommit"] == args.baseline
    actions = [
        ("open", "פתיחה"),
        ("scroll", "גלילה ראשונית"),
        ("jump_forward", "קפיצה קדימה"),
        ("jump_backward", "קפיצה אחורה"),
        ("warmup_complete", "יתרת המתנה לחימום"),
        ("steady_scroll", "גלילה לאחר טעינה"),
        ("close", "סגירה"),
    ]
    raw = {}
    process_ids = {}
    files = {}
    for side in ("baseline", "candidate"):
        manifest = json.loads((root / side / "manifest.json").read_text(encoding="utf-8-sig"))
        assert manifest["hardwareId"] == "github-hosted-" + args.run_id + "-1"
        path = root / side / "phases.jsonl"
        contents = path.read_bytes()
        rows = [json.loads(line) for line in contents.decode("utf-8-sig").splitlines() if line]
        raw[side] = [row for row in rows if row.get("type") == "phase" and not row.get("warmup")]
        process_ids[side] = sorted({row["launchIndex"] for row in raw[side]})
        assert len(process_ids[side]) == 4
        files[side] = {"sha256": hashlib.sha256(contents).hexdigest(), "bytes": len(contents)}

    assert process_ids == {"baseline": [0, 1, 2, 3], "candidate": [0, 1, 2, 3]}
    assert [(entry["side"], entry["launchIndex"]) for entry in provenance["launchOrder"]] == [
        ("baseline", 0), ("candidate", 0), ("candidate", 1), ("baseline", 1),
        ("baseline", 2), ("candidate", 2), ("candidate", 3), ("baseline", 3),
    ]
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 11, "axes.titlesize": 14})
    fig, axes = plt.subplots(2, 4, figsize=(17, 9.2), facecolor="white")
    colors = {"baseline": "#25658A", "candidate": "#AC4B17"}
    offsets = {"baseline": -0.13, "candidate": 0.13}
    audit = {"design": args.design, "run_id": args.run_id, "baseline": args.baseline,
             "candidate": args.candidate, "phase_files": files, "actions": {},
             "method": "All16 observations per side per action;4 process groups;arithmetic process medians;no filtering;no pooling across runs"}

    for ax, (action, title) in zip(axes.flat, actions):
        by_side = {}
        medians = {}
        for side in ("baseline", "candidate"):
            rows = [r for r in raw[side] if r["name"] == "book.long." + action]
            assert len(rows) == 16 and all(r["status"] == "passed" for r in rows)
            groups = []
            for index, launch_id in enumerate(process_ids[side], start=1):
                group = sorted((r for r in rows if r["launchIndex"] == launch_id), key=lambda r: r["iteration"])
                assert len(group) == 4 and [r["iteration"] for r in group] == [0, 1, 2, 3]
                values = [r["durationMs"] for r in group]
                groups.append({"launch_index": launch_id, "duration_ms": values, "arithmetic_median_ms": median(values)})
                xs = [index + offsets[side] + jitter for jitter in (-0.045, -0.015, 0.015, 0.045)]
                ax.scatter(xs, values, s=27, color=colors[side], alpha=0.8, zorder=3, linewidths=0.4, edgecolors="white")
                ax.plot([index + offsets[side] - 0.09, index + offsets[side] + 0.09], [median(values)] * 2,
                        color=colors[side], linewidth=2.6, zorder=4)
            by_side[side] = groups
            medians[side] = [g["arithmetic_median_ms"] for g in groups]
        for index in range(4):
            ax.plot([index + 1 - 0.13, index + 1 + 0.13],
                    [medians["baseline"][index], medians["candidate"][index]], color="#B9B9B9", linewidth=1, zorder=2)
        audit["actions"][action] = by_side
        ax.set_title(hebrew(title), pad=11)
        ax.set_xticks([1, 2, 3, 4])
        ax.set_xlim(0.55, 4.45)
        maximum = max(value for groups in by_side.values() for group in groups for value in group["duration_ms"])
        ax.set_ylim(0, maximum * 1.12)
        ax.yaxis.set_major_locator(MaxNLocator(nbins=5))
        ax.yaxis.set_major_formatter(FuncFormatter(lambda value, _: f"{value:,.0f}"))
        ax.set_xlabel(hebrew("זוג תהליכים"), labelpad=6)
        ax.set_ylabel(hebrew("מילישניות"), labelpad=6)
        ax.grid(axis="y", color="#E1E6EA", linewidth=0.7)
        ax.spines[["top", "right"]].set_visible(False)

    notes = axes.flat[-1]
    notes.axis("off")
    handles = [Line2D([0], [0], color=colors[side], marker="o", linestyle="", markersize=7,
                      label=hebrew(label)) for side, label in [("baseline", "בסיס"), ("candidate", "מועמד")]]
    notes.legend(handles=handles, loc="upper center", frameon=False, fontsize=13)
    descriptions = [
        "ארבעה תהליכים לכל צד",
        "ארבע חזרות מדודות בכל תהליך",
        "כל הדגימות מוצגות ללא סינון",
        "הפס מציין חציון חשבוני בתהליך",
        "הקו האפור מחבר חציונים בזוג",
        "זמן קצר יותר מופיע נמוך יותר",
        "ההמתנה כוללת בדיקת מוכנות",
        "המדידה בוצעה על חומרה וירטואלית",
    ]
    for index, description in enumerate(descriptions):
        notes.text(0.5, 0.71 - index * 0.087, hebrew(description), ha="center", va="center", fontsize=11)
    fig.suptitle(hebrew("ספר בן מיליון שורות — כל התצפיות לפי תהליך"), y=0.98, fontsize=21, fontweight="bold")
    fig.text(0.5, 0.935, f"{args.design} | run {args.run_id} | baseline {args.baseline[:12]} | candidate {args.candidate[:12]}",
             ha="center", fontsize=10.5, color="#475569")
    fig.subplots_adjust(left=0.065, right=0.985, top=0.86, bottom=0.08, wspace=0.39, hspace=0.52)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, dpi=160, metadata={"Software": "matplotlib; deterministic reader measurement visualization"})
    plt.close(fig)
    audit["figure_sha256"] = hashlib.sha256(args.output.read_bytes()).hexdigest()
    audit["observation_count"] = 7 * 16 * 2
    args.output.with_suffix(".json").write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"figure": str(args.output), "sha256": audit["figure_sha256"], "observations": audit["observation_count"]}))


if __name__ == "__main__":
    main()
