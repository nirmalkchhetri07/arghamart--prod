"use client";

import type { Category } from "@spree/sdk";
import { ChevronLeft, ChevronRight } from "lucide-react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useCallback, useRef, useState } from "react";
import type Swiper from "swiper";
import { Navigation } from "swiper/modules";
import { Swiper as SwiperComponent, SwiperSlide } from "swiper/react";
import "swiper/css";
import { CategoryImage } from "@/components/ui/category-image";

interface CategoryCarouselProps {
  categories: Category[];
  basePath: string;
}

export function CategoryCarousel({
  categories,
  basePath,
}: CategoryCarouselProps) {
  const t = useTranslations("home");
  const previousRef = useRef<HTMLButtonElement>(null);
  const nextRef = useRef<HTMLButtonElement>(null);
  const [isBeginning, setIsBeginning] = useState(true);
  const [isEnd, setIsEnd] = useState(categories.length <= 6);

  const updateNavigation = useCallback((swiper: Swiper) => {
    setIsBeginning(swiper.isBeginning);
    setIsEnd(swiper.isEnd);
  }, []);

  const attachNavigation = useCallback((swiper: Swiper) => {
    if (typeof swiper.params.navigation === "object") {
      swiper.params.navigation.prevEl = previousRef.current;
      swiper.params.navigation.nextEl = nextRef.current;
    }
  }, []);

  if (categories.length === 0) return null;

  return (
    <section
      aria-labelledby="shop-by-category"
      className="container mx-auto px-4 pb-4 pt-8 sm:px-6 lg:px-8"
    >
      <div className="mb-6 flex items-center justify-between gap-4">
        <h2
          id="shop-by-category"
          className="text-2xl font-semibold tracking-tight text-foreground"
        >
          {t("shopByCategory")}
        </h2>
        <div className="flex gap-2">
          <button
            ref={previousRef}
            type="button"
            aria-label="Previous categories"
            disabled={isBeginning}
            className="flex size-9 items-center justify-center rounded-full border border-border bg-background text-foreground transition-all duration-200 hover:border-primary/50 hover:bg-primary/5 hover:text-primary disabled:cursor-not-allowed disabled:opacity-35 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <ChevronLeft className="size-4" />
          </button>
          <button
            ref={nextRef}
            type="button"
            aria-label="Next categories"
            disabled={isEnd}
            className="flex size-9 items-center justify-center rounded-full border border-border bg-background text-foreground transition-all duration-200 hover:border-primary/50 hover:bg-primary/5 hover:text-primary disabled:cursor-not-allowed disabled:opacity-35 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <ChevronRight className="size-4" />
          </button>
        </div>
      </div>
      <SwiperComponent
        modules={[Navigation]}
        navigation={{ prevEl: previousRef.current, nextEl: nextRef.current }}
        onBeforeInit={attachNavigation}
        onAfterInit={updateNavigation}
        onSlideChange={updateNavigation}
        spaceBetween={12}
        slidesPerView={3.2}
        breakpoints={{
          640: { slidesPerView: 5.2, spaceBetween: 14 },
          1024: { slidesPerView: 8.2, spaceBetween: 16 },
          1280: { slidesPerView: 10.2, spaceBetween: 16 },
        }}
        className="category-carousel"
      >
        {categories.map((category) => (
          <SwiperSlide key={category.id}>
            <Link
              href={`${basePath}/c/${category.permalink}`}
              className="group block text-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <div className="relative aspect-square overflow-hidden rounded-2xl bg-slate-50 shadow-sm ring-1 ring-black/5 transition duration-300 hover:shadow-md">
                <CategoryImage
                  src={category.image_url}
                  alt={category.name}
                  fill
                  sizes="(max-width: 640px) 28vw, (max-width: 1024px) 18vw, 10vw"
                  className="object-contain p-4 transition-transform duration-500 ease-out group-hover:scale-105"
                />
              </div>
              <span className="mt-3 block truncate text-sm font-medium text-foreground/80 transition-colors duration-300 group-hover:text-foreground">
                {category.name}
              </span>
            </Link>
          </SwiperSlide>
        ))}
      </SwiperComponent>
    </section>
  );
}
