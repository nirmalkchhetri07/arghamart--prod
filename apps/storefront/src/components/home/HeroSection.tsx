import type { Category } from "@spree/sdk";
import { CategoryCarousel } from "@/components/home/CategoryCarousel";
import { HeroSlider } from "@/components/home/HeroSlider";
import { PromoCards } from "@/components/home/PromoCards";
import { getCategories } from "@/lib/data/categories";
import { findCategoryImage, HERO_SLIDES, PROMOTIONS } from "@/lib/data/home";

interface HeroSectionProps {
  basePath: string;
  locale: string;
}

function flattenCategories(categories: Category[]): Category[] {
  return categories.flatMap((category) => [
    category,
    ...(category.children ?? []),
  ]);
}

export async function HeroSection({ basePath, locale }: HeroSectionProps) {
  let categories: Category[] = [];

  try {
    const response = await getCategories(
      { depth_eq: 0, expand: ["children"] },
      { locale },
    );
    categories = flattenCategories(response.data ?? []).slice(0, 16);
  } catch (error) {
    console.error("HeroSection: failed to load categories", error);
  }

  const slides = HERO_SLIDES.map((slide) => ({
    ...slide,
    imageUrl: findCategoryImage(categories, slide.categoryHint) ?? undefined,
    href:
      slide.ctaHref ??
      (slide.productSlug
        ? `${basePath}/products/${slide.productSlug}`
        : `${basePath}/products`),
  }));

  return (
    <section className="border-b border-border/70 bg-[#fbfcfe]">
      <div className="container mx-auto px-4 pb-8 pt-5 sm:px-6 sm:pb-10 lg:px-8 lg:pt-7">
        <div className="grid gap-4 lg:grid-cols-[minmax(0,1.08fr)_minmax(0,0.92fr)] lg:items-stretch">
          <HeroSlider slides={slides} />
          <PromoCards
            promotions={PROMOTIONS}
            categories={categories}
            basePath={basePath}
          />
        </div>
        <CategoryCarousel categories={categories} basePath={basePath} />
      </div>
    </section>
  );
}
