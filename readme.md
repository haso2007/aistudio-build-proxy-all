# Docker版 aistudio-build-proxy
集成 无头浏览器 + Websocket代理

问题: ~~当前cookie导出方式导出的cookie可能时效较短.~~ 指纹浏览器导出cookie很稳

## 使用方法:
1. 导出Cookie到项目`camoufox-py/cookies/`文件夹下

    #### 更稳定的方法：
   用指纹浏览器开个新窗口登录 google, 然后到指纹浏览器`编辑窗口`，把 cookie 复制出来用，然后删除浏览器窗口就行，这个 cookie 超稳！！！

    <details>
       <summary>旧方法（不再推荐）：cookie很容易因为主账户的个人使用活动导致导出的cookie失效。</summary>
    (1) 安装导出Cookie的插件, 这里推荐 [Global Cookie Manager浏览器插件](https://chromewebstore.google.com/detail/global-cookie-manager/bgffajlinmbdcileomeilpihjdgjiphb)
    
    (2) 使用插件导出浏览器内所有涉及`google`的Cookie
    
    导出Cookie示例图:
    ![Global Cookie Manager](/img/Global_Cookie_Manager.png)
    ![Global Cookie Manager2](/img/Global_Cookie_Manager2.png)
    
    (3) 粘贴到项目 `camoufox-py/cookies/[自己命名].json` 中
    </details>
2. 修改浏览器配置`camoufox-py/config.yaml`

    (1) 在`camoufox-py`下, 将示例配置文件`config.yaml.example`, 重命名为 `config.yaml`, 然后修改`config.yaml`

    (2) 实例 1 的`cookie_file` 填入自己创建 cookie文件名

    (3) (可选项) `url` 默认为项目提供的AIStudio Build 链接(会连接本地5345的ws服务), 可修改为自己的

    (4) (可选项) proxy配置指定浏览器使用的代理服务器

3. 修改`docker-compose.yml`
    
    (1) 自己设置一个 `AUTH_API_KEY` , 最后自己调 gemini 时要使用该 apikey 调用, 不支持无 key
4. 在项目根目录, 通过`docker-compose.yml`启动Docker容器

    (1) 运行命令启动容器
    ```bash
    docker compose up -d
    ```

5. 等待一段时间后, 通过 http://127.0.0.1:5345 和 自己设置的`AUTH_API_KEY`使用.
    
    注1: 由于只是反代Gemini, 因此[接口文档](https://ai.google.dev/api)和Gemini API: `https://generativelanguage.googleapis.com`端点 完全相同, 使用只需将该url替换为`http://127.0.0.1:5345`即可, 支持原生Google Search、代码执行等工具。

    注2: Cherry Studio等工具使用时, 务必记得选择提供商为 `Gemini`。

## 日志查看
1. docker日志
```bash
docker logs [容器名]
```
2. 单独查看camoufox-py日志

    camoufox-py/logs/app.log

    且每次运行, logs下会有一张截图

## 容器资源占用:
![Containers Stats](/img/Containers_Stats.png)
本图为仅使用一个cookie的占用

## 运行效果示例:
快速模型首字吐出很快,表明该代理网络较好,本程序到google链路通畅

![running example](/img/running_example.gif)

如果使用推理模型慢,那就是 aistudio 的问题, 和本项目没关系

## 新增功能: 通过模型后缀启用 Google Search

为便于像 AI Studio 网页那样一键启用搜索工具, 现在可以在模型名后添加 `-search` 后缀, 代理会自动：

- 将模型名去掉 `-search` 后再转发到官方接口
- 默认仅注入 `toolConfig.googleSearchRetrieval.dynamicRetrievalConfig.mode = "MODE_DYNAMIC"`（更贴近网页行为）
- 如需同时注入 `tools.google_search`，设置环境变量 `SEARCH_INJECTION_WITH_TOOLS=true`

示例调用：

```
POST http://127.0.0.1:5345/v1beta/models/gemini-1.5-flash-search:generateContent?key=your_set_api_key_here
Content-Type: application/json

{
  "contents": [ { "role": "user", "parts": [ { "text": "今天的要闻是什么？" } ] } ]
}
```

你也可以使用 `gemini-2.5-pro-search` 等别名。若你已在请求体手动配置了 `tools` 或 `toolConfig`，代理不会覆盖已存在的同名字段，仅在缺失时补充。