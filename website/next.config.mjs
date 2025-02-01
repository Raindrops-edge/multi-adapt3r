import remarkGfm from "remark-gfm";
import remarkToc from "remark-toc";
import rehypePrettyCode from "rehype-pretty-code";
import rehypeSlug from "rehype-slug";
import createMDX from "@next/mdx";

/** @type {import('next').NextConfig} */
const nextConfig = {
  pageExtensions: ["js", "jsx", "mdx", "ts", "tsx"],
};

/** @type {import('rehype-pretty-code').Options} */
const prettyCodeOptions = {
  theme: {
    dark: "one-dark-pro",
    light: "one-dark-pro", // todo: when we support light mode
  },
};

const withMDX = createMDX({
  // Add markdown plugins here, as desired
  options: {
    remarkPlugins: [remarkGfm, remarkToc],
    rehypePlugins: [rehypeSlug, [rehypePrettyCode, prettyCodeOptions]],
  },
});

export default withMDX(nextConfig);
