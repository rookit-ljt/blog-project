import type { UIStrings } from "../types";

export default {
  nav: {
    home: "首页",
    posts: "文章",
    tags: "标签",
    about: "关于",
    archives: "归档",
    search: "搜索",
  },
  post: {
    publishedAt: "发布于",
    updatedAt: "更新于",
    sharePostIntro: "分享本文：",
    sharePostOn: "在 {{platform}} 上分享",
    sharePostViaEmail: "通过邮件分享",
    tagLabel: "标签",
    backToTop: "返回顶部",
    goBack: "返回上一页",
    editPage: "编辑本页",
    previousPost: "上一篇",
    nextPost: "下一篇",
  },
  pagination: {
    prev: "上一页",
    next: "下一页",
    page: "页码",
  },
  home: {
    socialLinks: "社交链接",
    featured: "精选文章",
    recentPosts: "近期发布",
    allPosts: "全部文章",
  },
  footer: {
    copyright: "版权所有",
    allRightsReserved: "保留所有权利。",
  },
  pages: {
    tagTitle: "标签",
    tagDesc: "所有包含此标签的文章",

    tagsTitle: "标签",
    tagsDesc: "博客文章所使用的全部标签。",

    postsTitle: "文章",
    postsDesc: "所有已发布的博文与技术实践。",

    archivesTitle: "归档",
    archivesDesc: "按时间归档的历史博文。",

    searchTitle: "搜索",
    searchDesc: "搜索博文与文章内容...",
  },
  a11y: {
    skipToContent: "跳转到正文",
    openMenu: "打开菜单",
    closeMenu: "关闭菜单",
    toggleTheme: "切换主题",
    searchPlaceholder: "搜索文章...",
    noResults: "未找到相关文章",
    goToPreviousPage: "前往上一页",
    goToNextPage: "前往下一页",
  },
  notFound: {
    title: "404 未找到页面",
    message: "抱歉，您访问的页面不存在。",
    goHome: "返回首页",
  },
} satisfies UIStrings;
