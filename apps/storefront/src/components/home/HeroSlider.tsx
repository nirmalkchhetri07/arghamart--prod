"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { useRef, useState } from "react";
import type Swiper from "swiper";
import { Autoplay, Keyboard } from "swiper/modules";
import { Swiper as SwiperComponent, SwiperSlide } from "swiper/react";
import "swiper/css";
import { Button } from "@/components/ui/button";
import type { HeroSlideContent } from "@/lib/data/home";

interface HeroSliderProps {
  slides: Array<HeroSlideContent & { imageUrl?: string; href: string }>;
}

export function HeroSlider({ slides }: HeroSliderProps) {
  const swiperRef = useRef<Swiper | null>(null);
  const [activeIndex, setActiveIndex] = useState(0);

  return (
    <div className="relative h-full overflow-hidden rounded-3xl bg-slate-950 shadow-2xl ring-1 ring-black/5">
      <SwiperComponent
        modules={[Autoplay, Keyboard]}
        autoplay={{
          delay: 5000,
          disableOnInteraction: false,
          pauseOnMouseEnter: true,
        }}
        keyboard={{ enabled: true }}
        loop={slides.length > 1}
        onSwiper={(swiper) => {
          swiperRef.current = swiper;
        }}
        onSlideChange={(swiper) => setActiveIndex(swiper.realIndex)}
        className="h-full"
      >
        {slides.map((slide, index) => (
          <SwiperSlide key={slide.title || `slide-${index}`} className="h-full">
            <div
              className={`relative isolate h-full min-h-[28rem] overflow-hidden bg-linear-to-br ${slide.tone} sm:min-h-[34rem]`}
            >
              <div className="absolute inset-0 bg-linear-to-t from-black/40 via-black/10 to-transparent" />

              {slide.backgroundVideoUrl && (
                <video
                  className="absolute inset-0 z-0 h-full w-full object-cover"
                  src={slide.backgroundVideoUrl}
                  autoPlay
                  muted
                  loop
                  playsInline
                  preload="metadata"
                />
              )}

              {slide.backgroundImageUrl && (
                <div
                  aria-hidden="true"
                  className="absolute inset-0 z-0 bg-cover bg-center"
                  style={{
                    backgroundImage: `url("${slide.backgroundImageUrl}")`,
                  }}
                />
              )}

              {slide.imageUrl && (
                <div className="absolute inset-y-0 right-[-4%] z-0 hidden w-[52%] lg:block">
                  <Image
                    src={slide.imageUrl}
                    alt=""
                    fill
                    priority={index === 0}
                    sizes="(min-width: 1024px) 28vw, 0px"
                    className="object-contain object-right drop-shadow-2xl"
                  />
                </div>
              )}

              <div className="relative z-10 flex h-full flex-col justify-end px-8 pb-12 sm:px-12 sm:pb-16 lg:max-w-[58%]">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.2em] text-white/80">
                    {slide.eyebrow}
                  </p>
                  {index === 0 ? (
                    <h1 className="mt-4 text-4xl font-semibold leading-[1.1] tracking-tight text-white sm:text-6xl">
                      {slide.title}
                    </h1>
                  ) : (
                    <p className="mt-4 text-4xl font-semibold leading-[1.1] tracking-tight text-white sm:text-6xl">
                      {slide.title}
                    </p>
                  )}
                  {slide.description && (
                    <p className="mt-4 max-w-md text-base leading-relaxed text-white/80 sm:text-lg">
                      {slide.description}
                    </p>
                  )}
                  <div className="mt-8">
                    <Button
                      asChild
                      className="h-12 rounded-xl bg-white px-6 text-sm font-semibold text-slate-900 shadow-xl transition hover:bg-white/90 hover:shadow-2xl"
                    >
                      <Link href={slide.href}>
                        {slide.cta}
                        <ChevronRight className="ml-1.5 size-4" />
                      </Link>
                    </Button>
                  </div>
                </div>
              </div>

              <div className="absolute inset-x-0 bottom-0 z-20 flex items-center justify-between px-6 pb-5 sm:px-10 sm:pb-8">
                <div
                  className="flex items-center gap-2"
                  role="tablist"
                  aria-label="Hero slides"
                >
                  {slides.map((_, index) => (
                    <button
                      key={index}
                      type="button"
                      role="tab"
                      aria-label={`Go to slide ${index + 1}`}
                      aria-selected={activeIndex === index}
                      onClick={() => swiperRef.current?.slideToLoop(index)}
                      className={`h-1 rounded-full transition-all duration-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white ${
                        activeIndex === index
                          ? "w-8 bg-white"
                          : "w-2 bg-white/40 hover:bg-white/70"
                      }`}
                    />
                  ))}
                </div>
                <div className="flex gap-2">
                  <button
                    type="button"
                    aria-label="Previous hero slide"
                    onClick={() => swiperRef.current?.slidePrev()}
                    className="flex size-10 items-center justify-center rounded-full border border-white/20 bg-white/10 text-white backdrop-blur-md transition hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
                  >
                    <ChevronLeft className="size-4" />
                  </button>
                  <button
                    type="button"
                    aria-label="Next hero slide"
                    onClick={() => swiperRef.current?.slideNext()}
                    className="flex size-10 items-center justify-center rounded-full border border-white/20 bg-white/10 text-white backdrop-blur-md transition hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
                  >
                    <ChevronRight className="size-4" />
                  </button>
                </div>
              </div>
            </div>
          </SwiperSlide>
        ))}
      </SwiperComponent>
    </div>
  );
}
