# 桌宠素材来源

## 当前打包：原版 DeepSeek 鲸鱼娘

- 上游：https://github.com/Sutera-Diffusus/dsh-whale-musume
- 固定版本：`94aec85bb14d4b46b773c0a6be4b6edc4a486120`
- 许可：MIT，`Copyright (c) 2026 Sutera-Diffusus`。原文保留于 `WhaleMusume/LICENSE`。
- `WhaleMusume/manifest.json` 记录每个原始文件的上游路径、字节数和 SHA-256。
- 原样收录 28 张 WebP 姿态图和 `whale-moe-core.js`。未重绘角色；原版 core 提供状态优先级、姿态名称和点击区域判断。
- `design/pet.js` 是 macOS / Magpie 适配层；`pet.css` 的呼吸、摇摆、压缩换姿态和互动粒子参考上游 MIT 代码，文件内保留来源署名。
- `build-app.sh` 打包到 `Contents/Resources/Pets/WhaleMusume/`，工作台装扮预览也引用同一资源。运行时没有外部素材请求。
- 七种待机装扮；请求状态使用原版工作姿态。这是多姿态 WebP + CSS/WAAPI 动效，不是 Live2D。未移植上游养成、成就和小游戏全部功能。

## 历史生成素材（保留来源，不再打包）

以下三张 PNG 是早期方案的独立生成素材，当前运行界面不再引用。生成日期 2026-10-23，使用内置 ImageGen，透明背景；保留完整原始提示供追溯。

## 原始生成提示

### whale-maid.png

最终文件：`Resources/Pets/whale-maid.png`

```text
Use case: stylized-concept. Asset type: transparent cutout character sprite for a premium macOS desktop companion. Create ONE original adorable whale-themed anime chibi girl, full body, 3-heads-tall proportions, polished Japanese gacha game illustration, extremely clean detailed lineart, luminous cel shading. Pearl white flowing hair with aqua tips, large expressive teal eyes, tiny blue whale tail hair clip, oversized navy and ivory sailor hoodie whose hood has small whale fins, tiny star charms, short skirt and stockings, chunky ocean boots. She floats gently with one hand slightly raised; playful warm smile, enchanting ocean magic. A small smooth blue whale spirit floating near her shoulder, connected visually as part of her silhouette. Tapered ribbon hair ends and fluttering sleeves. Beautiful cyan edge light, softly luminous accents. Centered portrait framing, complete silhouette with at least 9 percent transparent padding on all edges, no cropping at head/feet/hair. True transparent background, no ground, no shadow outside character, no scenery, no typography, no labels, no watermark. Character should be readable and delightful at 180px tall. Isolated original artwork, no logos or existing copyrighted character.
```

### star-fox.png

最终文件：`Resources/Pets/star-fox.png`

```text
Use case: stylized-concept. Asset type: transparent cutout character sprite for a premium macOS desktop companion. ONE adorable original celestial fox creature, full body, polished collectible 3D game mascot render, expressive large amber eyes, fluffy ivory fur with burnt orange ears and paws, two huge flowing tails with luminous golden tips curling around body, tiny midnight blue cape with gold clasps and small star charms, one forepaw raised. Fox animal, not human. Compact floating pose, captivating and elegant. Soft dimensional lighting, exquisite groomed fur with readable broad shapes, warm golden rim highlights. Centered portrait framing, complete silhouette within central 78 percent of image, ample clear transparent margin on every side. True transparent background alpha, absolutely no background glow or colored backdrop, no floor or cast shadow, no text, no typography, no watermarks, no cropped tail. Readable at 180px tall.
```

### orbit-bot.png

最终文件：`Resources/Pets/orbit-bot.png`

```text
Use case: stylized-concept. Asset type: one original transparent cutout mascot for a premium macOS desktop pet. Full body adorable floating orbital robot, small round pearl-white ceramic body, oversized spherical helmet with glossy dark navy visor and two expressive cyan crescent eyes, little magnetic mitten hands, tiny boot thrusters, asymmetric antenna with glowing mint tip, one thin tilted Saturn-like gold ring around its body. Precise exquisite 3D animated movie toy render, soft dimensional studio light and turquoise rim light, premium material texture, friendly energetic pose, one arm waving. Complete centered silhouette with ample transparent padding on every edge. Portrait composition, readable at 180px tall. TRUE TRANSPARENT ALPHA background. No colored backdrop, no environmental glow, no floor, no cast shadow, no words or watermark. Not a human. Original character.
```

