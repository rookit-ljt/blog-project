import { defineAstroPaperConfig } from "./src/types/config";

export default defineAstroPaperConfig({
  site: {
    url: "https://blog.techvar.top",
    title: "rookie_L",
    description: "记录前端工程、Claude Code、Agent 和 AI 应用开发实践。",
    author: "李金涛",
    profile: "https://satna.ing",
    ogImage: "default-og.jpg",
    lang: "zh-CN",
    timezone: "Asia/Shanghai",
    dir: "ltr",
  },
  posts: {
    perPage: 4,
    perIndex: 4,
    scheduledPostMargin: 15 * 60 * 1000,
  },
  features: {
    lightAndDarkMode: true,
    // Use the bundled default image until a server-side font is configured.
    dynamicOgImage: false,
    showArchives: true,
    showBackButton: true,
    editPost: {
      enabled: true,
      url: "https://github.com/rookit-ljt/blog-project/edit/main/",
    },
    search: "pagefind",
  },
  socials: [
    { name: "github", url: "https://github.com/rookit-ljt" },
  ],
  shareLinks: [],
});
