import type { Category } from "@spree/sdk";

export interface HeroSlideContent {
  eyebrow: string;
  title: string;
  description: string;
  cta: string;
  ctaHref?: string;
  categoryHint: string;
  tone: string;
  backgroundImageUrl?: string;
  backgroundVideoUrl?: string;
  productSlug?: string;
}

export interface PromoContent {
  eyebrow: string;
  title: string;
  description: string;
  cta: string;
  ctaHref?: string;
  categoryHint: string;
  tone: string;
  backgroundImageUrl?: string;
  backgroundVideoUrl?: string;
}

export const HERO_SLIDES: HeroSlideContent[] = [
  // {
  //   eyebrow: "Seasonal savings",
  //   title: "Monsoon deals are pouring in.",
  //   description: "Discover standout prices on electronics and home appliances.",
  //   cta: "Shop now",
  //   ctaHref: "",
  //   categoryHint: "Electronics",
  //   tone: "from-[#0b2439] via-[#0d4c63] to-[#087f8c]",
  //   backgroundImageUrl: "",
  //   backgroundVideoUrl: "",
  // },
  // {
  //   eyebrow: "Home cinema",
  //   title: "Upgrade your entertainment.",
  //   description: "Smart TVs and audio systems that make every night better.",
  //   cta: "Explore TVs",
  //   ctaHref: "",
  //   categoryHint: "TVs",
  //   tone: "from-[#191331] via-[#3a2666] to-[#ce5c51]",
  //   backgroundImageUrl: "",
  //   backgroundVideoUrl: "",
  // },
  // {
  //   eyebrow: "Home refresh",
  //   title: "Power up your home.",
  //   description: "Save more on the appliances built for everyday Nepal.",
  //   cta: "View appliances",
  //   ctaHref: "",
  //   categoryHint: "Home Appliances",
  //   tone: "from-[#2d241d] via-[#8b4d27] to-[#e4a447]",
  //   backgroundImageUrl: "",
  //   backgroundVideoUrl: "",
  // },
  // {
  //   eyebrow: "Level up",
  //   title: "Build your gaming setup.",
  //   description:
  //     "Performance parts, consoles and accessories for your next win.",
  //   cta: "Shop gaming",
  //   ctaHref: "",
  //   categoryHint: "PC Components",
  //   tone: "from-[#101d31] via-[#155f72] to-[#32b3a5]",
  //   backgroundImageUrl: "",
  //   backgroundVideoUrl: "",
  // },
  {
    eyebrow: "Flash Sale",
    title: "Khaitan Induction Cooker",
    description:
      "Induction Cooktop Worktop Material:Crystal Power Consumption: 2000 W Color: Black Push Button Controls",
    cta: "Buy Now",
    ctaHref: "/np/en/products/khaitan-induction-cooker-ka-412-2000w",
    categoryHint: "Home Appliances",
    tone: "from-[#261a24] via-[#8b335b] to-[#ed785a]",
    backgroundImageUrl: "",
    backgroundVideoUrl:
      "https://pub-aff09554fee54c3b89a4770115242a28.r2.dev/public_videos/promotion.mp4",
  },
];

export const PROMOTIONS: PromoContent[] = [
  {
    eyebrow: "Limited-Time Deal",
    title: "Save up to 5% on Electronics",
    description: "Upgrade your tech without stretching your budget.",
    cta: "Shop Now",
    categoryHint: "Electronics",
    tone: "from-[#eef5ff] to-[#d7e6ff]",
  },
  {
    eyebrow: "Best products",
    title: "",
    description: "",
    cta: "Shop now",
    categoryHint: "Induction Cookers",
    tone: "from-[#e7faf6] to-[#b9ebe0]",
    backgroundVideoUrl:
      "https://pub-aff09554fee54c3b89a4770115242a28.r2.dev/public_videos/promotion.mp4",
  },
  {
    eyebrow: "",
    title: "",
    description: "",
    cta: "Shop Now",
    categoryHint: "Water Purifiers",
    tone: "from-[#fff3e7] to-[#f9d6b8]",
    backgroundImageUrl: "",
    backgroundVideoUrl:
      "https://pub-aff09554fee54c3b89a4770115242a28.r2.dev/public_videos/KENT_water_purifier_commercial_a%E2%80%A6_20260914122851.mp4",
  },
  {
    eyebrow: "",
    title: "",
    description: "",
    cta: "Shop Now",
    categoryHint: "CCTV Cameras",
    tone: "from-[#fff3e7] to-[#f9d6b8]",
    backgroundImageUrl: "",
    backgroundVideoUrl:
      "https://pub-aff09554fee54c3b89a4770115242a28.r2.dev/public_videos/Smart_WiFi_camera_commercial_1080p_20260914123026.mp4",
  },
];

export function findCategoryImage(categories: Category[], hint: string) {
  const normalizedHint = hint.toLowerCase();
  return categories.find((category) =>
    category.name.toLowerCase().includes(normalizedHint),
  )?.image_url;
}
