# Generate video QA questions from Framepad projects

Copy this prompt into Codex and replace the inputs below. Each project corresponds to one video.

## Inputs

- Framepad projects: `<absolute paths to one or more .framepad projects>`
- Output directory: `<directory for generated CSVs>`
- Optional benchmark examples or additional column rules: `<paths, or none>`
- Target per video: **30 SHORT + 30 MEDIUM + 30 LONG questions**, unless I specify another count.

## Task

Build an egocentric video question-answering benchmark from my marked-up projects. Use only textual and binary answers, not timestamp answers or position coordinates. Include a varied mix of human/object attributes, qualitative spatial relationships, and actions between people and objects; avoid concentrating mostly on clothing colors.

Do not alter my original projects or videos. Make copies of the projects before extracting information or opening them in a way that could save changes. Work from those copies.

Inspect the annotations, saved captures, timestamps, and meaningful groups. Use the original videos for targeted checks when notes or images do not establish an answer. Do not treat annotations as infallible or invent details to reach a quota.

## Identification and definitiveness

Every question must have one clearly supported answer. Identify the intended subject using visible landmarks, location, distinctive encounters, or first/last relationships. Avoid ambiguous references when several people or objects could fit.

Groups named `SPECIAL: <unique-name>` mark distinctive objects that anchor the route. Use these landmarks to distinguish encounters, for example the first scooter rider after a particular sign. Describe the visible landmark naturally; do not require the answering system to know internal group names or vbox IDs.

**Do not include timestamps, elapsed-time intervals, or frame numbers in question text.** We want to test memory and retrieval, not a system's ability to parse a supplied timestamp. Keep evidence timing exclusively in `time_segments`.

Examples of the intended style:

- “What color was the minibus crossing in front of us at the large junction after the flat canopy?”
- “Were the scooter riders' tops at the roadworks and beside the mall the same color?”
- “Was the child on the shared scooter in front of the adult or behind him?”

These examples illustrate wording only; do not assume their events occur in the supplied videos. Do not put the requested answer into the subject description, such as calling a sign blue while asking for its color. Make the reference frame clear for left/right or in-front/behind relationships.

## Required authoring order

1. **Write SHORT questions first.** Build a grounded pool of local observations and questions for every video. You may collect more supporting short facts than the final requested count. Finish and provide each video's SHORT CSV before starting its MEDIUM/LONG output.
2. **Derive MEDIUM and LONG questions afterward.** Use the short questions and their supporting observations to compare or connect encounters. Recheck video evidence only where needed. Do not merely pad a local question with unrelated timestamps to make it appear long-term.
3. **Review the results.** Remove duplicates and ambiguous questions, verify answers and evidence, and check the requested counts. If there is insufficient reliable material, report the shortfall instead of fabricating questions.

## CSV format

Use UTF-8 CSV with exactly these columns, in this order:

```csv
question_group,question_type,question,answer,time_segments
```

| Column | Requirements |
| :--- | :--- |
| `question_group` | `SHORT`, `MEDIUM`, or `LONG`. SHORT needs one moment or nearby moments spanning less than 30 seconds. MEDIUM connects separate encounters or intermediate sequences. LONG needs several relevant observations distributed across the video. Classify by evidence needed for the answer, not the effort required to find a subject. |
| `question_type` | `textual` or `binary`. |
| `question` | A concise, definitive question without timestamp hints. |
| `answer` | A clear canonical textual answer, or lowercase `true` / `false` for binary questions. For multipart questions, give components in the requested order. |
| `time_segments` | Sufficient evidence intervals, with millisecond precision: `[[00:02:35.223-00:02:37.156], [00:03:12.223-00:03:51.923]]`. Sort intervals, merge overlaps, and stay within video bounds. |

For first/last-subject questions, include evidence of that subject; you do not need the entire preceding/following video just to prove its encounter order. For aggregate questions, include all observations needed to establish the answer. Avoid whole-video counts unless the video has been reviewed sufficiently to support them.

Quote CSV fields containing commas, quotes, or newlines. Retain accurate evidence intervals; displaying milliseconds does not justify guessing event boundaries.

## Deliverables

- `<video-name>_short.csv`: the completed SHORT questions, supplied first.
- `<video-name>_medium_long.csv`: the MEDIUM and LONG questions, supplied afterward.
- A brief review note stating counts, evidence sources, and any unresolved limitations. Keep traceability to source vboxes in a separate supporting file if useful, without adding columns to the CSV.

Keep outputs separate for each video. For evaluation, supply the video and question to the answering system; retain answers and evidence metadata as ground truth.
