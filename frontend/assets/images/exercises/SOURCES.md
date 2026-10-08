# Reviewed workout exercise images

Original Developer-approved batch: B4, C1, P1 (preserved). Additional images below were selected under Developer authorization on 2026-10-08. Crops use pixel coordinates [left, top, right, bottom] of the verified downloaded source. JPEG quality 87, progressive, optimized; Lanczos resize; metadata omitted. The original batch contains no retouching, recoloring or generated content. The completion batch includes explicitly marked AI illustrations and neutral padding.

## B4: dumbbell-bench-press

- Source page: https://www.pexels.com/photo/a-man-doing-a-dumbbell-chest-press-7289237/
- Photographer: Alesia Kozik
- License: Pexels License, https://www.pexels.com/license/
- Attribution: not required; photographer / Pexels credit appreciated. Do not imply endorsement.
- Approved source file outside repository: `C:/Users/GL/AppData/Local/Temp/saman-exercise-photo-review-20261008-round2/7289237.jpg`
- Source SHA-256: `6a2f0a79aca02180b12070c675145d009f30f5d53a2625df3e69693c63897b1a`
- Source dimensions: 1800 x 1200; downloaded full-frame derivative, not native original.
- Thumbnail: `dumbbell-bench-press-thumb.jpg`, crop [200, 0, 1400, 1200] -> 512 x 512.
- Poster: `dumbbell-bench-press-poster.jpg`, crop [0, 150, 1800, 1162] -> 1280 x 720.

## C1: dumbbell-bicep-curl

- Source page: https://www.pexels.com/photo/photo-of-male-gymnast-doing-dumbbell-bicep-curls-3763115/
- Photographer: Andrea Piacquadio
- License: Pexels License, https://www.pexels.com/license/
- Attribution: not required; photographer / Pexels credit appreciated. Do not imply endorsement.
- Approved source file outside repository: `C:/Users/GL/AppData/Local/Temp/saman-exercise-photo-review-20261008/3763115.jpg`
- Source SHA-256: `dd5333f82c79b26b3fbbcd77ba83295255e4622c926afadb87392201d8e7665c`
- Source dimensions: 1800 x 1236; downloaded full-frame derivative, not native original.
- Thumbnail: `dumbbell-bicep-curl-thumb.jpg`, crop [390, 0, 1626, 1236] -> 512 x 512.
- Poster: `dumbbell-bicep-curl-poster.jpg`, crop [0, 105, 1800, 1117] -> 1280 x 720.

## P1: plank

- Source page: https://www.pexels.com/photo/man-in-gray-shirt-planking-4944959/
- Photographer: Anastasia Shuraeva
- License: Pexels License, https://www.pexels.com/license/
- Attribution: not required; photographer / Pexels credit appreciated. Do not imply endorsement.
- Approved source file outside repository: `C:/Users/GL/AppData/Local/Temp/saman-exercise-photo-review-20261008/4944959.jpg`
- Source SHA-256: `efd08349f3c4d3aeb11628966fba0ac91cb9f0d63c8c09bd8737229f81ce707d`
- Source dimensions: 1800 x 1200; downloaded full-frame derivative, not native original.
- Thumbnail: `plank-thumb.jpg`, crop [300, 0, 1500, 1200] -> 512 x 512.
- Original approval was thumbnail only. Thumbnail P1 remains byte-identical; the independently sourced full-body poster is documented below.

## Mapping and scope

Library IDs: `db-bench-press`, `db-bicep-curl`, `plank`. Legacy default `ex_1` refers to `db-bench-press`: verified by the existing alias in `session_detail_screen.dart` and `session_detail_screen_test.dart`. Only its image source changes; IDs and set targets remain intact.

Poster variants are declared beside the curated data in `exercise_providers.dart`, keyed by the existing thumbnail source. Thumbnails use cover at 68 x 68 / 80 x 80 (Review uses 48 x 48); Detail/Active/Review posters use contain inside existing frames. Neutral padding preserves decisive equipment when a crop is not 1:1 or 16:9. Browser verification reproduced a Review banner showing bench press for a Plank session: Review now resolves the poster from the performed exercise sources. A single exercise uses its own poster; mixed sessions and unknown sources use the shared neutral fallback. Dynamic plans with unresolved identity retain their existing empty source. Other session-wide hero images remain unchanged.

## Completion batch: 2026-10-08

All selected originals and final crops were viewed directly. Prefer real adult male photographs; AI is used when the bounded source search did not establish a suitable real photograph. AI illustrations identify exercises and equipment; **they are not verified exercise-form instruction**. No P3 Plank is used. B4/C1/P1 asset bytes are preserved. JPEG quality 87, progressive, optimized, Lanczos resize, metadata omitted. Coordinates are [left, top, right, bottom] in downloaded/generated pixels. Crops are proportionally contained with neutral RGB (18, 20, 23) padding; no stretching, recoloring or retouching. Generated originals remain at their tool-provided local paths; final JPEGs are bundled in this directory.

Real-photo usage follows the [Pexels License](https://www.pexels.com/license/), which permits use in apps and modifications. Attribution is not required; photographer credit is retained here. Do not imply endorsement. AI outputs are created for this task using the built-in OpenAI image_gen tool with no reference inputs. Their usage follows applicable OpenAI terms linked per entry (output ownership is distinct from a third-party stock license); no claim of exclusivity or certified form is made.

### dumbbell-shoulder-press (photo)

- Creator/photographer: Alesia Kozik
- Source: https://www.pexels.com/photo/a-man-doing-a-dumbbell-shoulder-press-7289370/
- License/usage: Pexels License; https://www.pexels.com/license/
- Original local file: `C:\Users\GL\AppData\Local\Temp\saman-workout-images-20261008\7289370.jpg`
- Original SHA-256: `901a5ce26111a69a874a6ac189ea13a1170795eb0c8733d235bde8038d2ba616`
- Original dimensions: 1800 x 1200. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Seated upright bench, two dumbbells at shoulder height. Clothing includes jeans; correct exercise/equipment and usable crop take priority.
- `dumbbell-shoulder-press-thumb.jpg`: crop [380, 0, 1580, 1200] -> contain 512 x 512 at offset [0, 0] in 512 x 512; 45064 bytes; SHA-256 `4e20b62265c3f6b5a70af9ded972852f645553ce89a71fc954a765833d8e9366`.
- `dumbbell-shoulder-press-poster.jpg`: crop [0, 40, 1800, 1150] -> contain 1168 x 720 at offset [56, 0] in 1280 x 720; 108319 bytes; SHA-256 `dd4adc384cb8cb7845e4dc3a58c0e870615c66f153eac3ca91d91d190aa44989`.

### push-up (photo)

- Creator/photographer: Ketut Subiyanto
- Source: https://www.pexels.com/photo/man-in-gray-tank-top-doing-push-ups-4720304/
- License/usage: Pexels License; https://www.pexels.com/license/
- Original local file: `C:\Users\GL\AppData\Local\Temp\saman-workout-images-20261008\4720304.jpg`
- Original SHA-256: `5f9a785f461b0c3cdccfe39bb5a57e9c5773484966b86e43939a6eac91f8e028`
- Original dimensions: 1800 x 1200. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Hands on floor, straight arms in top push-up position, both feet supported.
- `push-up-thumb.jpg`: crop [250, 0, 1450, 1200] -> contain 512 x 512 at offset [0, 0] in 512 x 512; 52623 bytes; SHA-256 `e94970fd25437e0cf161462dcc4da3101ffa0cdb6b523ba18c178a784bdc726c`.
- `push-up-poster.jpg`: crop [230, 160, 1530, 1190] -> contain 909 x 720 at offset [185, 0] in 1280 x 720; 122933 bytes; SHA-256 `8b4e3264d32e834a7a7ff03e8533095fc9a0c342a0477b148af43669d1c80933`.

### barbell-back-squat (photo)

- Creator/photographer: Airam Dato-on
- Source: https://www.pexels.com/photo/man-lifting-a-barbell-13106591/
- License/usage: Pexels License; https://www.pexels.com/license/
- Original local file: `C:\Users\GL\AppData\Local\Temp\saman-workout-images-20261008\13106591.jpg`
- Original SHA-256: `ee939c2257ff29bf7b30d4a97c9db11297f2eadcfa9c253df2aecec332e75724`
- Original dimensions: 1800 x 2700. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Bar behind head across shoulders, flexed knees, feet and loaded plates visible.
- `barbell-back-squat-thumb.jpg`: crop [300, 350, 1800, 1850] -> contain 512 x 512 at offset [0, 0] in 512 x 512; 39564 bytes; SHA-256 `028731348e6586cfe5f12e7e45dfe3d3a8d70dddee0b6e771c03247d2536fbc6`.
- `barbell-back-squat-poster.jpg`: crop [300, 550, 1800, 1700] -> contain 939 x 720 at offset [170, 0] in 1280 x 720; 98320 bytes; SHA-256 `c0e9e6412fa6e7150b98837c4d33a0e0ddf373747bb5bdc10466235aff8ff0ee`.

### leg-press (photo)

- Creator/photographer: @marcuschanmedia | IG
- Source: https://www.pexels.com/photo/bodybuilder-using-leg-press-at-the-gym-18060020/
- License/usage: Pexels License; https://www.pexels.com/license/
- Original local file: `C:\Users\GL\AppData\Local\Temp\saman-workout-images-20261008\18060020.jpg`
- Original SHA-256: `44c8cb330cd99c85f15fa15a4de7bee923845c62c93b44430612e7218f54f6b7`
- Original dimensions: 1800 x 1440. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Inclined sled machine, feet on platform, bent knees, supported back; crop retains platform.
- `leg-press-thumb.jpg`: crop [0, 150, 1800, 1440] -> contain 512 x 367 at offset [0, 72] in 512 x 512; 36079 bytes; SHA-256 `bf4f50e62495384d216edac87240fe70dcdf1ca1a43ff58952a188b47d19600a`.
- `leg-press-poster.jpg`: crop [0, 150, 1800, 1440] -> contain 1005 x 720 at offset [137, 0] in 1280 x 720; 102171 bytes; SHA-256 `032c1eb7177cb88fe201847e12dbdac9f13ade221228bfb002088444c69534a6`.

### ab-wheel-rollout (photo)

- Creator/photographer: Miguel Gonz?lez
- Source: https://www.pexels.com/photo/a-man-using-an-ab-wheel-14679048/
- License/usage: Pexels License; https://www.pexels.com/license/
- Original local file: `C:\Users\GL\AppData\Local\Temp\saman-workout-images-20261008\14679048.jpg`
- Original SHA-256: `28e83490eefe54053720fcbca8ac9cb4cf0899f4bf750027f9fab584598575d4`
- Original dimensions: 1800 x 2700. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Kneeling ab-wheel start/return position; both handles, wheel and knees visible.
- `ab-wheel-rollout-thumb.jpg`: crop [240, 650, 1740, 2150] -> contain 512 x 512 at offset [0, 0] in 512 x 512; 55538 bytes; SHA-256 `fe969b15ca82e84408d4e3740053617de1f99d837941997f823e70314f55247a`.
- `ab-wheel-rollout-poster.jpg`: crop [240, 820, 1740, 2170] -> contain 800 x 720 at offset [240, 0] in 1280 x 720; 109051 bytes; SHA-256 `a9703d3ae53457b1a8afc13fa65a2917987c74b2def361e303cde5383ed5b385`.

### plank (photo)

- Creator/photographer: ShotPot
- Source: https://www.pexels.com/photo/man-in-black-shorts-doing-planking-4047103/
- License/usage: Pexels License; https://www.pexels.com/license/
- Original local file: `C:\Users\GL\AppData\Local\Temp\saman-workout-images-20261008\4047103.jpg`
- Original SHA-256: `4824bd76ea769204095459b6950b7cd574307b20cd11316d747fa92f764379cd`
- Original dimensions: 1800 x 2700. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Forearms on mat, full torso and legs visible, including prosthetic leg. Full body preserved; existing P1 thumbnail retained.
- `plank-poster.jpg`: crop [0, 1080, 1800, 2140] -> contain 1223 x 720 at offset [28, 0] in 1280 x 720; 129305 bytes; SHA-256 `828bcafe5eb078049194d8cfe316ff2ab65566b604daa9344224092dd15017a7`.

### lat-pulldown (AI)

- Creator/photographer: OpenAI image_gen (prompt authored by Codex for this task)
- Source: Local generated output; no external stock photo page
- License/usage: AI output: applicable OpenAI terms, Content / Ownership of content; not a stock-photo license; https://openai.com/policies/terms-of-use/
- Original local file: `C:\Users\GL\.codex\generated_images\01a1196b-99b1-7d72-b07f-5db72ce3ec3b\exec-01ac4b90-b16d-48cc-9c67-258993b47951.png`
- Original SHA-256: `42c0ed0fe08ca7b483a42d55d165e28ee8a0bd3de06ba07d7fdd6375a2ce54df`
- Original dimensions: 1536 x 1024. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Wide overhand grip, front-of-head lat bar, overhead cable, seated thigh pad. Also mapped to legacy ex_2 with the same wide-grip variant.
- `lat-pulldown-thumb.jpg`: crop [400, 0, 1424, 1024] -> contain 512 x 512 at offset (0, 0) in 512 x 512; 49153 bytes; SHA-256 `b3f27c76bfe5312d1745dca22c0ba39cb0dd55f6271d0a6621a5fa0a4bc926de`.
- `lat-pulldown-poster.jpg`: crop [0, 0, 1536, 1024] -> contain 1080 x 720 at offset (100, 0) in 1280 x 720; 138842 bytes; SHA-256 `de5c55452542979c95719a5b2b02c9f25cb9f0524e8a2cf7b1eb4120f005bd8d`.

<details><summary>Exact AI generation prompt</summary>

Use case: photorealistic-natural. Asset type: Saman workout exercise identification poster, wide landscape 1536x1024. Create one photograph-like AI illustration of an adult male athlete in dark shorts and gray athletic shirt performing a seated wide overhand grip LAT PULLDOWN to the upper chest in a dark professional gym. Full body and full recognizable apparatus visible: seated on lat pulldown bench, thighs secured below thigh pad, feet planted, cable descends from overhead pulley and attaches to the center of a wide curved lat bar, both hands wider than shoulders holding the bar near upper chest, elbows down, torso upright slight lean, bar in FRONT of head. Realistic cable routing, equipment geometry, hands and anatomy. Side three-quarter camera, clear view of both grip positions and overhead cable. Center athlete and decisive apparatus within central square region so square thumbnail can retain bar, grip, torso and seat. Restrained charcoal gym, enough neutral light to clearly see equipment. No text, logos, watermark, arrows, panels, mirrors, other people. Exercise identification visual, not certified technique instruction.

</details>

### seated-cable-row (AI)

- Creator/photographer: OpenAI image_gen (prompt authored by Codex for this task)
- Source: Local generated output; no external stock photo page
- License/usage: AI output: applicable OpenAI terms, Content / Ownership of content; not a stock-photo license; https://openai.com/policies/terms-of-use/
- Original local file: `C:\Users\GL\.codex\generated_images\01a1196b-99b1-7d72-b07f-5db72ce3ec3b\exec-d90cc64b-ea7a-4f27-9941-0f2c6e2b1b95.png`
- Original SHA-256: `9e17c9b528e37f322eaf68689b693741e68c06b55125732f05335ddd53d2be93`
- Original dimensions: 1536 x 1024. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Seated bench, V-bar close grip, horizontal low cable, feet braced; no rowing ergometer.
- `seated-cable-row-thumb.jpg`: crop [60, 0, 1300, 1024] -> contain 512 x 423 at offset (0, 44) in 512 x 512; 41926 bytes; SHA-256 `c7bfb3f011ebeb1a1412a6057df66bc8244e3887dc65afa856bc6fe3725e994c`.
- `seated-cable-row-poster.jpg`: crop [0, 0, 1536, 1024] -> contain 1080 x 720 at offset (100, 0) in 1280 x 720; 129077 bytes; SHA-256 `7281959ce9b9ce0651496f359c1b236ca5d0ee4d9357821f7b6a0925992a6c3f`.

<details><summary>Exact AI generation prompt</summary>

Use case: photorealistic-natural. Create a single landscape 1536x1024 photograph-like AI illustration for Saman Workout exercise identification. One adult male in charcoal shorts, fitted gray sports shirt and training shoes, dark gym with restrained neutral light, realistic anatomy and apparatus. Show whole body and decisive equipment, no text/logos/watermark/arrows/collages/other people. Three-quarter side camera. Center the athlete and decisive apparatus within a square-friendly area, preserve enough margins for landscape poster. Identification illustration, not certified form instruction. SEATED CABLE ROW with close-grip metal V-bar. Man seated upright on low row bench facing weight stack, feet braced on two footplates, knees slightly bent, pulling V handle to lower ribs with elbows back. ONE visible taut cable runs HORIZONTALLY from V handle toward LOW front pulley near floor, mechanically connected to weight stack. Show both feet, bench, V bar, and low cable clearly; not a cardio rowing ergometer.

</details>

### triceps-rope-pushdown (AI)

- Creator/photographer: OpenAI image_gen (prompt authored by Codex for this task)
- Source: Local generated output; no external stock photo page
- License/usage: AI output: applicable OpenAI terms, Content / Ownership of content; not a stock-photo license; https://openai.com/policies/terms-of-use/
- Original local file: `C:\Users\GL\.codex\generated_images\01a1196b-99b1-7d72-b07f-5db72ce3ec3b\exec-07b74522-5e2e-46f7-a9c9-039869908a48.png`
- Original SHA-256: `163ac5a5b51c703a1117ab77755a3dc74dbbed51c50f0a0d091e9eb68c33e4c9`
- Original dimensions: 1536 x 1024. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Standing extension downward; two rope ends with stops and high cable.
- `triceps-rope-pushdown-thumb.jpg`: crop [480, 0, 1504, 1024] -> contain 512 x 512 at offset (0, 0) in 512 x 512; 46272 bytes; SHA-256 `437e62a666e978fd82a01246f3a980549a0f83eab3f50ac899a1a4528aef5d9e`.
- `triceps-rope-pushdown-poster.jpg`: crop [0, 0, 1536, 1024] -> contain 1080 x 720 at offset (100, 0) in 1280 x 720; 119572 bytes; SHA-256 `e8eb6d0cfb16928f7baac1a2e9d940548d40c5d674df494a38fdca0daf3ac509`.

<details><summary>Exact AI generation prompt</summary>

Use case: photorealistic-natural. Create a single landscape 1536x1024 photograph-like AI illustration for Saman Workout exercise identification. One adult male in charcoal shorts, fitted gray sports shirt and training shoes, dark gym with restrained neutral light, realistic anatomy and apparatus. Show whole body and decisive equipment, no text/logos/watermark/arrows/collages/other people. Three-quarter side camera. Center the athlete and decisive apparatus within a square-friendly area, preserve enough margins for landscape poster. Identification illustration, not certified form instruction. TRICEPS ROPE PUSHDOWN standing facing cable tower, elbows next to ribs, arms extended down, grasping two ends of black braided rope with rubber end stops near outer thighs. Rope center connects by carabiner to ONE cable rising to HIGH pulley above athlete. Rope clearly split, NOT a metal straight bar, NOT overhead extension. Both hands, elbows, rope and high cable visible.

</details>

### romanian-deadlift (AI)

- Creator/photographer: OpenAI image_gen (prompt authored by Codex for this task)
- Source: Local generated output; no external stock photo page
- License/usage: AI output: applicable OpenAI terms, Content / Ownership of content; not a stock-photo license; https://openai.com/policies/terms-of-use/
- Original local file: `C:\Users\GL\.codex\generated_images\01a1196b-99b1-7d72-b07f-5db72ce3ec3b\exec-cc023eb0-e3b1-4863-93eb-017081081f97.png`
- Original SHA-256: `adeee13127591111850e8471ab9049c5e638ee77dd762b60a2e69f0c865ee333`
- Original dimensions: 1536 x 1024. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Hip hinge, slightly bent knees, bar below knees and above floor; no conventional floor deadlift.
- `romanian-deadlift-thumb.jpg`: crop [350, 0, 1374, 1024] -> contain 512 x 512 at offset (0, 0) in 512 x 512; 40924 bytes; SHA-256 `79583adc211b3d6cb9c43278f34b3fe717989b4d287b273781f311f010a3bbf9`.
- `romanian-deadlift-poster.jpg`: crop [0, 0, 1536, 1024] -> contain 1080 x 720 at offset (100, 0) in 1280 x 720; 105910 bytes; SHA-256 `665d1be7dfdaee5316b05aa63a02a83eb5b0eae718021ece2b8dbf3478b1bb43`.

<details><summary>Exact AI generation prompt</summary>

Use case: photorealistic-natural. Create a single landscape 1536x1024 photograph-like AI illustration for Saman Workout exercise identification. One adult male in charcoal shorts, fitted gray sports shirt and training shoes, dark gym with restrained neutral light, realistic anatomy and apparatus. Show whole body and decisive equipment, no text/logos/watermark/arrows/collages/other people. Three-quarter side camera. Center the athlete and decisive apparatus within a square-friendly area, preserve enough margins for landscape poster. Identification illustration, not certified form instruction. BARBELL ROMANIAN DEADLIFT at bottom of hip hinge: side view of man with hips pushed BACK, knees only slightly bent and shins nearly vertical, torso angled forward with neutral straight back, both hands holding barbell with modest round plates just below knee level and close to shins. Both feet planted, elbows straight; bar suspended above ground. Not a conventional floor deadlift or squat. Full body, bar and plates visible.

</details>

### barbell-hip-thrust (AI)

- Creator/photographer: OpenAI image_gen (prompt authored by Codex for this task)
- Source: Local generated output; no external stock photo page
- License/usage: AI output: applicable OpenAI terms, Content / Ownership of content; not a stock-photo license; https://openai.com/policies/terms-of-use/
- Original local file: `C:\Users\GL\.codex\generated_images\01a1196b-99b1-7d72-b07f-5db72ce3ec3b\exec-29c1808b-ca26-4436-9aed-591dfb803529.png`
- Original SHA-256: `ba2ea43ac4edf7482b09d88f1f0c1c3bc7933a5065b8c4976bb2a8732847a113`
- Original dimensions: 1254 x 1254. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Upper back on bench, padded bar across hips, bent knees and planted feet.
- `barbell-hip-thrust-thumb.jpg`: crop [0, 0, 1254, 1254] -> contain 512 x 512 at offset (0, 0) in 512 x 512; 54489 bytes; SHA-256 `5b386ee7ed3f8ae92286ead035adc73f98c86199fb930f4f94682fdf57f9ac97`.
- `barbell-hip-thrust-poster.jpg`: crop [0, 0, 1254, 1254] -> contain 720 x 720 at offset (280, 0) in 1280 x 720; 104039 bytes; SHA-256 `881c1af68dc583c2f3ef5db284720cb6e31cd3705a5a2c55687dedf140658503`.

<details><summary>Exact AI generation prompt</summary>

Single landscape photograph-like AI exercise illustration, adult male in gray sports shirt and black shorts, dark gym. Full body and apparatus, realistic anatomy, no text logos watermark. Square-friendly composition. Not verified form instruction. BARBELL HIP THRUST at top, side three-quarter view. Man with upper back and shoulder blades resting across edge of horizontal flat bench, hips elevated, knees bent 90 degrees, shins vertical, both feet planted on floor in front of bench. Padded barbell lies HORIZONTALLY across HIP CREASE, hands steady bar; plates on each end visible. Torso almost horizontal between shoulders and knees. Show bench, both feet, padded bar and plates. No hip thrust machine or floor glute bridge.

</details>

### lying-leg-curl (AI)

- Creator/photographer: OpenAI image_gen (prompt authored by Codex for this task)
- Source: Local generated output; no external stock photo page
- License/usage: AI output: applicable OpenAI terms, Content / Ownership of content; not a stock-photo license; https://openai.com/policies/terms-of-use/
- Original local file: `C:\Users\GL\.codex\generated_images\01a1196b-99b1-7d72-b07f-5db72ce3ec3b\exec-95dec64d-008e-4e2b-913c-83b5c5b193f6.png`
- Original SHA-256: `3437ec8d2f369ffa768076f30b0af16df3766b901567432f0fa46ee1524c3d4a`
- Original dimensions: 1254 x 1254. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Prone body on machine, flexed knees and roller against lower calves.
- `lying-leg-curl-thumb.jpg`: crop [0, 0, 1254, 1254] -> contain 512 x 512 at offset (0, 0) in 512 x 512; 55789 bytes; SHA-256 `630a43ee4c6d92a68b7c04a5de7a735c234b3cbcdf70b68378777319c36eab09`.
- `lying-leg-curl-poster.jpg`: crop [0, 0, 1254, 1254] -> contain 720 x 720 at offset (280, 0) in 1280 x 720; 104247 bytes; SHA-256 `73390198b564fa03e5d4fd0c764b5d545610b7ce97acb3e72a5b1f0663b52c40`.

<details><summary>Exact AI generation prompt</summary>

Single landscape photograph-like AI exercise illustration, adult male in gray sports shirt and black shorts, dark gym. Full body and apparatus, realistic anatomy, no text logos watermark. Square-friendly composition. Not verified form instruction. LYING LEG CURL on prone leg curl weight machine. Side view adult man lies FACE DOWN, chest and hips supported on padded machine bench, grasps handles at head end. Both knees bent about 70 degrees bringing heels UP toward buttocks, black cylindrical roller pad rests against backs of lower calves/above ankles and is attached to metal lever beside machine. Clearly show lying prone posture, roller at ankles, bent knees, feet, machine pivot and weight stack. Not leg extension or seated curl.

</details>

### standing-calf-raise (AI)

- Creator/photographer: OpenAI image_gen (prompt authored by Codex for this task)
- Source: Local generated output; no external stock photo page
- License/usage: AI output: applicable OpenAI terms, Content / Ownership of content; not a stock-photo license; https://openai.com/policies/terms-of-use/
- Original local file: `C:\Users\GL\.codex\generated_images\01a1196b-99b1-7d72-b07f-5db72ce3ec3b\exec-31559830-a457-4be3-944f-37f789a1bb45.png`
- Original SHA-256: `1eac175422eeaf44f53b91b2512c6a9664d0a9e9507c2b6a88807ae6e22ee6af`
- Original dimensions: 1254 x 1254. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Standing machine shoulder pads, straight knees, balls of feet on block, raised unsupported heels.
- `standing-calf-raise-thumb.jpg`: crop [0, 0, 1254, 1254] -> contain 512 x 512 at offset (0, 0) in 512 x 512; 47251 bytes; SHA-256 `5538122dd5077b5c94d7423ab47a6fea826dbee201cc8f77b2ad8120d8cb888b`.
- `standing-calf-raise-poster.jpg`: crop [0, 0, 1254, 1254] -> contain 720 x 720 at offset (280, 0) in 1280 x 720; 87830 bytes; SHA-256 `f7c87c1252621d68c93dc38f5ca2991f455f57658da8d41044c23c3baf42954f`.

<details><summary>Exact AI generation prompt</summary>

Single landscape photograph-like AI exercise illustration, adult male in gray sports shirt and black shorts, dark gym. Full body and apparatus, realistic anatomy, no text logos watermark. Square-friendly composition. Not verified form instruction. STANDING CALF RAISE machine, side three-quarter view. Man stands straight under two shoulder pads attached to lever of weight stack machine, hands grip handles next to shoulders. Both knees straight, balls of feet on edge of elevated small calf block, HEELS clearly lifted and hanging free beyond platform edge. Show both training shoes, toes on block, visibly elevated heels, shoulder pads and machine stack. Not squat, seated calf raise or leg press.

</details>

### hanging-leg-raise (AI)

- Creator/photographer: OpenAI image_gen (prompt authored by Codex for this task)
- Source: Local generated output; no external stock photo page
- License/usage: AI output: applicable OpenAI terms, Content / Ownership of content; not a stock-photo license; https://openai.com/policies/terms-of-use/
- Original local file: `C:\Users\GL\.codex\generated_images\01a1196b-99b1-7d72-b07f-5db72ce3ec3b\exec-50646ef8-d9f0-4338-a301-ea3dd82604f7.png`
- Original SHA-256: `fafd0487513cad3883950fce613d32bfbdaba5f9cb65efe1ca57ec985f2a75c0`
- Original dimensions: 1536 x 1024. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Both hands on overhead bar, arms straight, legs raised together; no captain chair.
- `hanging-leg-raise-thumb.jpg`: crop [330, 0, 1354, 1024] -> contain 512 x 512 at offset (0, 0) in 512 x 512; 38857 bytes; SHA-256 `eb0ba1876cde2ff49b4209240213d8b5a9d8898c462c439df1a8b43d16bb5f24`.
- `hanging-leg-raise-poster.jpg`: crop [0, 0, 1536, 1024] -> contain 1080 x 720 at offset (100, 0) in 1280 x 720; 104159 bytes; SHA-256 `926e687a3ccab86f66f5af80dfad587196fbdf5dac327a6762ee9f51812ff3f7`.

<details><summary>Exact AI generation prompt</summary>

Use case: photorealistic-natural. Create a single landscape 1536x1024 photograph-like AI illustration for Saman Workout exercise identification. One adult male in charcoal shorts, fitted gray sports shirt and training shoes, dark gym with restrained neutral light, realistic anatomy and apparatus. Show whole body and decisive equipment, no text/logos/watermark/arrows/collages/other people. Three-quarter side camera. Center the athlete and decisive apparatus within a square-friendly area, preserve enough margins for landscape poster. Identification illustration, not certified form instruction. HANGING STRAIGHT LEG RAISE. Adult man hangs by BOTH HANDS gripping fixed overhead pullup bar of power rack, arms straight overhead, shoulders engaged. Both legs together lifted FORWARD horizontally at hip height, knees nearly straight, toes forward, whole body suspended OFF floor with no elbow pads or backrest. Three-quarter side camera so hands on bar, straight arms, torso, legs and shoes all visible. Not captain's chair, pullup, knee raise or dip.

</details>

### cable-woodchopper (AI)

- Creator/photographer: OpenAI image_gen (prompt authored by Codex for this task)
- Source: Local generated output; no external stock photo page
- License/usage: AI output: applicable OpenAI terms, Content / Ownership of content; not a stock-photo license; https://openai.com/policies/terms-of-use/
- Original local file: `C:\Users\GL\.codex\generated_images\01a1196b-99b1-7d72-b07f-5db72ce3ec3b\exec-d6792e7e-0f03-4d53-aa34-b02a71cfb78b.png`
- Original SHA-256: `65fee671455533b7d77dfec322c3794872fe9c6f8991ac5a63c353b917a60aec`
- Original dimensions: 1536 x 1024. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: High-to-low diagonal cable, two hands on one handle, standing rotational stance.
- `cable-woodchopper-thumb.jpg`: crop [370, 0, 1390, 1024] -> contain 510 x 512 at offset (1, 0) in 512 x 512; 43258 bytes; SHA-256 `78d904a25730bc40fce2b40aa6799ed7d0ae2ed0e83917f0d8f17de2aa07ad93`.
- `cable-woodchopper-poster.jpg`: crop [0, 0, 1536, 1024] -> contain 1080 x 720 at offset (100, 0) in 1280 x 720; 112119 bytes; SHA-256 `74307568e0388c51c1e4d0b9d2f8499ce64e88eb90d066fce524e7fa68358c0b`.

<details><summary>Exact AI generation prompt</summary>

Use case: photorealistic-natural. Create a single landscape 1536x1024 photograph-like AI illustration for Saman Workout exercise identification. One adult male in charcoal shorts, fitted gray sports shirt and training shoes, dark gym with restrained neutral light, realistic anatomy and apparatus. Show whole body and decisive equipment, no text/logos/watermark/arrows/collages/other people. Three-quarter side camera. Center the athlete and decisive apparatus within a square-friendly area, preserve enough margins for landscape poster. Identification illustration, not certified form instruction. STANDING HIGH-TO-LOW CABLE WOODCHOPPER. Adult man stands sideways to tall cable tower with feet apart, softly bent knees. Both hands together gripping ONE D-handle near opposite hip in end of diagonal rotational pull. ONE taut cable runs diagonally UP from hands to high pulley on tower at his side. Upper torso rotated toward low hands while pelvis stable. Show both hands, grip handle, diagonal cable, high pulley and planted feet clearly. Not battle ropes or vertical triceps pushdown.

</details>

### incline-dumbbell-flyes (AI)

- Creator/photographer: OpenAI image_gen (prompt authored by Codex for this task)
- Source: Local generated output; no external stock photo page
- License/usage: AI output: applicable OpenAI terms, Content / Ownership of content; not a stock-photo license; https://openai.com/policies/terms-of-use/
- Original local file: `C:\Users\GL\.codex\generated_images\01a1196b-99b1-7d72-b07f-5db72ce3ec3b\exec-584330ab-9460-4489-a508-a6fa4b3020c4.png`
- Original SHA-256: `cd4a0f42652ce88a4e8a73934f47d5bfbb656a1452a97785dcb99627036acbe3`
- Original dimensions: 1536 x 1024. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Inclined bench, two dumbbells, open arms with slight elbow bend. Legacy ex_3 only; never reuse flat bench press.
- `incline-dumbbell-flyes-thumb.jpg`: crop [220, 70, 1380, 960] -> contain 512 x 393 at offset (0, 59) in 512 x 512; 37603 bytes; SHA-256 `f357140d241a8e35068a04464976bef94db25507e9fa84f886903b2b3a8a74f3`.
- `incline-dumbbell-flyes-poster.jpg`: crop [0, 0, 1536, 1024] -> contain 1080 x 720 at offset (100, 0) in 1280 x 720; 119496 bytes; SHA-256 `54a435ed56e18e3ec431d939f300beda88dfaf046a18bc0583c45b87c490fe12`.

<details><summary>Exact AI generation prompt</summary>

Use case: photorealistic-natural. Create a single landscape 1536x1024 photograph-like AI illustration for Saman Workout exercise identification. One adult male in charcoal shorts, fitted gray sports shirt and training shoes, dark gym with restrained neutral light, realistic anatomy and apparatus. Show whole body and decisive equipment, no text/logos/watermark/arrows/collages/other people. Three-quarter side camera. Center the athlete and decisive apparatus within a square-friendly area, preserve enough margins for landscape poster. Identification illustration, not certified form instruction. INCLINE DUMBBELL FLYES, adult male lies supine on bench backrest raised 30 degrees, feet planted. BOTH arms open WIDE to sides at chest level with only slight FIXED elbow bend (about 160 degrees), one dumbbell in each hand, palms facing each other. Mid lowering arc, chest open. Show inclined bench angle, both dumbbells and open long arms clearly, front three-quarter side camera. NOT dumbbell bench press, not flat flyes, not shoulder press. Full body with visible bench and feet.

</details>

### overhead-triceps-extension (AI)

- Creator/photographer: OpenAI image_gen (prompt authored by Codex for this task)
- Source: Local generated output; no external stock photo page
- License/usage: AI output: applicable OpenAI terms, Content / Ownership of content; not a stock-photo license; https://openai.com/policies/terms-of-use/
- Original local file: `C:\Users\GL\.codex\generated_images\01a1196b-99b1-7d72-b07f-5db72ce3ec3b\exec-072f4d1c-34ad-4594-abc7-e84008f74f1f.png`
- Original SHA-256: `f03cee7deb9a9412a6bf4406d02ba305cf7ff59f2921afa7a5dc6ed1078c4f72`
- Original dimensions: 1536 x 1024. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: One dumbbell supported by two hands behind head, elbows up, seated upright. Legacy ex_4 only; not rope pushdown.
- `overhead-triceps-extension-thumb.jpg`: crop [350, 0, 1374, 1024] -> contain 512 x 512 at offset (0, 0) in 512 x 512; 41815 bytes; SHA-256 `5b236b58f1b4f1b39bea34244c2288fa05fc2512d41e16b2f808ae45a6b84a98`.
- `overhead-triceps-extension-poster.jpg`: crop [0, 0, 1536, 1024] -> contain 1080 x 720 at offset (100, 0) in 1280 x 720; 107683 bytes; SHA-256 `4f0fb27d4e5699fff3381e8bd5738fec86efc5d3bb06c270c211b3e99c8f9bb3`.

<details><summary>Exact AI generation prompt</summary>

Use case: photorealistic-natural. Create a single landscape 1536x1024 photograph-like AI illustration for Saman Workout exercise identification. One adult male in charcoal shorts, fitted gray sports shirt and training shoes, dark gym with restrained neutral light, realistic anatomy and apparatus. Show whole body and decisive equipment, no text/logos/watermark/arrows/collages/other people. Three-quarter side camera. Center the athlete and decisive apparatus within a square-friendly area, preserve enough margins for landscape poster. Identification illustration, not certified form instruction. DUMBBELL TWO-HAND OVERHEAD TRICEPS EXTENSION. Adult male seated upright on vertical-backed bench, feet planted, BOTH upper arms beside head pointing nearly straight up, elbows bent so ONE vertical dumbbell hangs BEHIND head. Both hands together cup inside of upper dumbbell plate above/behind crown, elbows point up. Side three-quarter view shows bent elbows, hands supporting ONE dumbbell, second lower plate behind head and vertical backrest. Not shoulder press, not two dumbbells, not cable.

</details>

### face-pulls (AI)

- Creator/photographer: OpenAI image_gen (prompt authored by Codex for this task)
- Source: Local generated output; no external stock photo page
- License/usage: AI output: applicable OpenAI terms, Content / Ownership of content; not a stock-photo license; https://openai.com/policies/terms-of-use/
- Original local file: `C:\Users\GL\.codex\generated_images\01a1196b-99b1-7d72-b07f-5db72ce3ec3b\exec-6a2be9af-f784-49af-af3f-bec788b9e7d1.png`
- Original SHA-256: `022f2a462072d1bda342b1a188338ef67326e359bf892bc4c089640f33ed0070`
- Original dimensions: 1536 x 1024. Photo downloads are full-frame 1800px derivatives, not native originals.
- Visual review: Rope at face level, high/horizontal cable, raised wide elbows. Legacy ex_5 only.
- `face-pulls-thumb.jpg`: crop [320, 0, 1360, 1024] -> contain 512 x 504 at offset (0, 4) in 512 x 512; 44221 bytes; SHA-256 `a25634bdd8b64faedac67f47e34e1622ef90dc42f43f9ce6407800da10f39a85`.
- `face-pulls-poster.jpg`: crop [0, 0, 1536, 1024] -> contain 1080 x 720 at offset (100, 0) in 1280 x 720; 125600 bytes; SHA-256 `0818c593ccbb2ad876573d49f1a84e2ee9bbd50b2af8a3b7ebcd1e5bce5fa2b6`.

<details><summary>Exact AI generation prompt</summary>

Use case: photorealistic-natural. Create a single landscape 1536x1024 photograph-like AI illustration for Saman Workout exercise identification. One adult male in charcoal shorts, fitted gray sports shirt and training shoes, dark gym with restrained neutral light, realistic anatomy and apparatus. Show whole body and decisive equipment, no text/logos/watermark/arrows/collages/other people. Three-quarter side camera. Center the athlete and decisive apparatus within a square-friendly area, preserve enough margins for landscape poster. Identification illustration, not certified form instruction. CABLE ROPE FACE PULL at contracted phase. Adult man stands facing cable tower, feet planted slightly staggered, torso upright. HIGH pulley at HEAD level, ONE horizontal taut cable runs from tower to center clip of black braided two-ended rope at face level. Both hands hold rubber rope ends beside temples, elbows wide and raised to SHOULDER height, upper arms horizontal, forearms bend back vertically, external rotation. Clearly show cable, forked rope, both hands near temples and elbows wide. Not triceps pushdown, upright row or rope curl. Three-quarter side view.

</details>

## Bounded candidate review

No motion exceeded three visually reviewed candidates. Search result listings are discovery only; a listing/title or HTTP success was never accepted as visual evidence.

- Lat pulldown: Pexels 31849599 viewed, behind-head/front bar placement unclear from rear angle; rejected for default Wide Grip reuse. One AI candidate selected (2 reviewed total).
- Seated cable row: targeted Pexels search exposed a video, not a suitable reviewed still; one AI candidate selected.
- Shoulder press: Pexels 7289370 viewed and selected (1).
- Push-up: Pexels 13916678 viewed but too tight/front-on for full-body poster; Pexels 4720304 selected (2).
- Rope pushdown: Pexels 6243176 viewed, rigid bar attachment; rejected. One AI rope candidate selected (2).
- Back squat: Pexels 116077 viewed, front squat; rejected. Pexels 13106591 selected (2).
- Romanian deadlift, hip thrust, lying leg curl, standing calf raise, hanging leg raise, cable woodchopper: bounded targeted Pexels searches produced no suitable still with verified motion; one AI candidate each selected (1 per motion).
- Leg press: Pexels 5799855 viewed, foot/platform occlusion; Pexels 18060020 selected (2).
- Ab wheel: Pexels 8032892 viewed, wheel cropped at bottom and bright home setting; Pexels 14679048 selected (2).
- Plank poster: Pexels 4047103 selected (1 new candidate). P3 not used or relied on.
- Default Active incline flyes, dumbbell overhead extension, face pulls: targeted searches did not establish appropriate stills; one AI candidate each selected. All legacy IDs and session fields preserved.
