---
name: qa-generation
description: Generate grounded egocentric video QA datasets from annotated Framepad projects. Use when creating short-, medium-, and long-term questions from saved vboxes, notes, and landmark groups, or expanding an existing benchmark with attribute, spatial, or action questions.
---

# Framepad QA generation

Turn annotated `.framepad` projects into questions with definitive answers and traceable video evidence. Each project corresponds to one video.

## Establish the scope

Use the user's project paths, output directory, requested question counts, topic mix, and any existing benchmark examples. Ask for missing project paths. If counts are unspecified, aim for 30 SHORT, 30 MEDIUM, and 30 LONG questions per video. Respect smaller review or generation budgets.

Default to textual and binary answers, with a mix of attributes, qualitative spatial relationships, and actions. Avoid concentrating mostly on clothing colors. For additions to an existing benchmark, preserve its files and check for duplicate questions.

## Read Framepad evidence

Copy each project before extracting or opening it. Work from the copies and leave original projects and videos unchanged. Resolve the referenced video when targeted checks are needed. If it is unavailable, use saved captures only where they establish the answer and report gaps.

A `.framepad` package contains `project.json` and `captures/`. In the current format, `items` contains either `box._0` for an ungrouped vbox or `group._0` with `title`, `prompt`, and `boxes`. Each vbox has an `id`, `prompt`, `time`, `frameIndex`, and an optional `imageFile`. Convert rational time as `time.value / time.timescale`. Capture paths are relative to `captures/`. Inspect the actual schema rather than assuming every version is identical.

Read annotations and inspect saved images. Notes are useful evidence, not infallible ground truth. Cropped images may omit context needed for spatial questions. Inspect the original video when motion, identity, or relative position is uncertain. Do not fabricate details to reach a quota.

Groups named `SPECIAL: <name>` identify distinctive landmarks that divide the route into recognizable sections. Translate those internal labels into natural descriptions of visible objects.

## Write questions in order

1. **Finish SHORT questions first.** Build a local fact bank from the reviewed evidence. You may retain more supporting facts than the requested number of questions. Write and provide each video's SHORT CSV before starting its MEDIUM/LONG file.
2. **Derive MEDIUM and LONG questions.** Compare or connect the short facts and revisit video evidence only where needed. Use genuinely relevant observations, not unrelated intervals added to inflate a question's horizon.
3. **Review and deliver.** Check definitive subject identification, answers, evidence coverage, duplicates, and requested counts. Report any shortfall instead of inventing questions.

## Make questions definitive

- Identify subjects through visible landmarks, location, distinctive encounters, or first/last relationships. Avoid references that fit several subjects.
- Do not include timestamps, elapsed-time intervals, frame numbers, or internal vbox/group IDs in question text. Keep timing exclusively in evidence metadata.
- Do not reveal the answer in the identifying phrase, such as calling a sign blue while asking its color.
- State the reference frame for ambiguous spatial relations. Distinguish the camera wearer's left from an approaching person's own left.
- Use textual spatial descriptions, not coordinates. Do not ask for timestamp answers.
- Restrict counts to identifiable groups or listed encounters unless sufficient video review supports a whole-video total.

Useful wording patterns include “What color was the minibus crossing in front of us at the large junction after the flat canopy?” and “Were the scooter riders' tops at the roadworks and beside the mall the same color?” Treat these as examples of identification, not facts about a new video.

## CSV contract

Write UTF-8 CSV with exactly these columns:

```csv
question_group,question_type,question,answer,time_segments
```

| Column | Requirements |
| :--- | :--- |
| `question_group` | `SHORT`, `MEDIUM`, or `LONG`. SHORT needs one moment or nearby moments spanning less than 30 seconds. MEDIUM connects separate encounters or intermediate sequences. LONG needs several relevant observations distributed across the video. Classify by the evidence needed to answer, not search effort. |
| `question_type` | `textual` or `binary`. |
| `question` | A concise, definitive question without timestamp hints. |
| `answer` | A canonical textual answer, or lowercase `true` / `false`. Give multipart answers in the requested order. |
| `time_segments` | Sufficient evidence intervals with millisecond precision, such as `[[00:02:35.223-00:02:37.156], [00:03:12.223-00:03:51.923]]`. Sort intervals, merge overlaps, and stay within video bounds. |

For first/last-subject questions, include the identified subject's evidence without the entire preceding/following video merely to prove encounter order. Aggregate questions need evidence for every observation used in the answer. Preserve timing accuracy without claiming that retrieval windows are exact event boundaries.

Quote CSV fields containing commas, quotes, or newlines. Validate schema, allowed values, binary literals, duplicate questions within each video, interval ordering and bounds, and SHORT evidence spans. Structural validation does not establish semantic correctness. Match visual review depth to the user's request and state what was checked.

## Deliverables

- `<video-name>_short.csv`, completed and supplied first.
- `<video-name>_medium_long.csv`, containing the subsequent MEDIUM and LONG questions.
- A brief review note with counts, evidence sources, and unresolved limitations.

Keep each video's outputs separate. Record source vbox IDs and supporting observations in a separate evidence file when useful, without adding CSV columns. For evaluation, provide the video and question to the answering system and retain answers and evidence as ground truth.
