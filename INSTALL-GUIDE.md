# dsh-opencode-free-models 安装教程（小白版）

> 给完全不懂技术的用户看。照着一步一步做就行，不用理解原理。

---

## 一、这个插件是干什么的？

装好之后，你的 **DeepSeek Harness** 里会多出一批**免费、不用填密钥**的模型（Big Pickle、MiMo、混元 Hunyuan、Nemotron、Muse Spark 等），直接在聊天框右下角的「模型」里选就能用。

- ✅ **不需要 API key / 密钥**，开箱即用。
- ✅ 装好重启就出现，不用手动配置。
- ✅ 免费模型由插件自动接入官方免费档，随官方更新自动增减。

---

## 二、安装前，请先确认两件事

1. 你已经安装并正常运行 **DeepSeek Harness**（桌面版 exe 或网页版都行）。
2. 你能找到 DeepSeek Harness 装在哪（一般会自动找到；找不到时下面有办法）。

---

## 三、方法一：一键安装（推荐，最简单）

你会拿到一个文件夹，里面至少有：**`安装.bat`**（也叫 `install.bat`）、`卸载.bat`、`重启.bat`、和一个 `plugin` 文件夹。

> ⚠️ **整个文件夹要放在一起**，不要只复制单独的 `.bat` 文件。

**步骤：**

1. **右键 `安装.bat` → 以管理员身份运行**。（Win11 直接双击通常也行，但用管理员更稳。）
2. 会弹出一个黑色窗口，自动查找你电脑上的 DeepSeek Harness：
   - 如果只找到一处 → 自动装好。
   - 如果找到好几处 → 会列出 `[0]` `[1]` …，让你输入数字选装到哪；输入 `a` 表示全部都装。
3. 看到「**插件已安装！**」就成功了，关闭黑窗口即可。

**如果提示“没有找到 DeepSeek Harness”：**
- 确认软件确实已安装并打开过；
- 或设置环境变量 `DSH_HOME` 指向 DeepSeek Harness 的根目录（就是那个**包含 `profiles` 文件夹**的目录），然后重新运行 `安装.bat`。

---

## 四、方法二：手动安装（一键装不上时用）

1. 打开文件夹 `plugin\dsh-opencode-free-models`。
2. 把它**整个复制**，粘贴到：
   `<DeepSeek Harness 根目录>\profiles\web\node_modules\`
   （没有 `node_modules` 文件夹就自己新建一个）。
   最终路径应长这样：
   `…\profiles\web\node_modules\dsh-opencode-free-models\`
3. 用记事本打开 `<DeepSeek Harness 根目录>\profiles\web\package.json`。
4. 在 `dependencies` 里加一行（版本号看插件里的 package.json，一般是 `"0.1.0"`）：
   ```json
   "dsh-opencode-free-models": "0.1.0"
   ```
5. 找到 `dsh.profile.bundles`（是一个列表），把 `"dsh-opencode-free-models"` 加进去。
6. 保存文件。

---

## 五、重启 DeepSeek Harness（必须做！）

装完**一定要重启软件**，插件才会生效。

- 最简单：双击 `重启.bat`（会先关掉再重新打开 DeepSeek Harness）。
- 或手动：完全退出 DeepSeek Harness（包括右下角托盘图标），再重新打开。

> **如果当前 harness 打不开、报「Failed to load plugins / bundle script ... failed to load」**：多半是之前用旧版 `卸载.bat` 卸载到一半（找不到 pnpm）导致插件处于半装状态。处理办法：
> 1. 到插件市场里找到 `dsh-opencode-free-models`，若显示「卸载」就点它把它卸干净；
> 2. 或手动删掉 `…\profiles\web\node_modules\dsh-opencode-free-models` 这个文件夹，并把 `…\profiles\web\package.json` 里 `dependencies` 的 `"dsh-opencode-free-models": "..."` 和 `dsh.profile.bundles` 里的 `"dsh-opencode-free-models"` 删掉；
> 3. 重启 DeepSeek Harness——此时应能正常打开。
> 之后再重新运行 `安装.bat` 装一次即可。

---

## 六、怎么确认装好了 / 怎么用

1. 重新打开 DeepSeek Harness。
2. 主界面**左侧边缘**会多出一个 **🎁 免费模型** 按钮。点开是一个「免费模型」面板，可以看模型列表和公告。
3. **直接用**：在聊天输入框**右下角的「模型」选择框**里，就能看到 `opencode-free / …` 开头的免费模型，点选它就能对话，**全程不需要任何密钥**。
   - 提醒：免费模型是插件自动接好的。面板里的「一键置入」按钮现在只是提示，不用点，也不用填任何东西。

---

## 七、怎么卸载

在 DeepSeek Harness 的**插件市场**里找到 `dsh-opencode-free-models`，点「卸载」即可。卸载后重启 DeepSeek Harness 就生效。

> 说明：本次分发包已移除 `卸载.bat`，请勿再使用旧版安装目录里残留的 `卸载.bat`。

---

## 八、常见问题（FAQ）

**Q1：装完左侧没有 🎁 按钮？**
- 多半是没重启，或装到了另一个 DeepSeek Harness 实例。请完全退出再重开；若电脑装了多个 DSH，重跑 `安装.bat` 选对那一个。
- 也可以自己检查：路径 `…\profiles\web\node_modules\dsh-opencode-free-models\lib\client.cjs` 是否存在。

**Q2：按钮在，但模型选择框里没有免费模型？**
- 可能是免费档临时维护（站长关了总开关），等一会儿或联系插件提供方。
- 或你的 DeepSeek Harness 版本太旧，请更新软件。

**Q3：需要填密钥 / API key 吗？**
- **不需要。** 这是官方免费档，插件已经自动配置好。任何让你填 key 的提示，都不是本插件要求的。

**Q4：安全吗？**
- 插件不收集你的聊天内容、不要求密钥、代码开源可查。免费模型由官方免费档提供。

---

## 九、给站长 / 提供方的提示（可选）

- 免费模型列表由后端控制（上下架、可用时间窗），站长在后端 `/admin/opencode` 管理。
- 若用户面板一直“加载中”或报错，通常是后端地址不可达或跨域（CORS）未放行，请确认后端已把 DeepSeek Harness 页面来源加入白名单。

---

> 分发说明：请把**整个 `one-click-install` 文件夹**发给用户即可（里面已包含改好的插件，无需用户再下载别的东西）。
