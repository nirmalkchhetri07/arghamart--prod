import type { Category } from "@spree/sdk";
import Image from "next/image";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { findCategoryImage, type PromoContent } from "@/lib/data/home";

interface PromoCardsProps {
  promotions: PromoContent[];
  categories: Category[];
  basePath: string;
}

export function PromoCards({
  promotions,
  categories,
  basePath,
}: PromoCardsProps) {
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
      {promotions.map((promotion, index) => {
        const imageUrl = findCategoryImage(categories, promotion.categoryHint);
        const ctaHref =
          promotion.ctaHref ??
          `${basePath}/products?category=${encodeURIComponent(promotion.categoryHint)}`;

        return (
          <article
            key={promotion.title || `${promotion.categoryHint}-${index}`}
            className={`group relative min-h-72 overflow-hidden rounded-2xl bg-linear-to-br ${promotion.tone} shadow-sm ring-1 ring-black/5 transition duration-300 hover:-translate-y-0.5 hover:shadow-lg`}
          >
            <div className="absolute inset-0 bg-linear-to-t from-black/30 via-black/5 to-transparent" />

            {promotion.backgroundVideoUrl && (
              <video
                className="absolute inset-0 z-0 h-full w-full object-cover"
                src={promotion.backgroundVideoUrl}
                autoPlay
                muted
                loop
                playsInline
                preload="metadata"
              />
            )}

            {promotion.backgroundImageUrl && (
              <div
                aria-hidden="true"
                className="absolute inset-0 z-0 bg-cover bg-center"
                style={{
                  backgroundImage: `url("${promotion.backgroundImageUrl}")`,
                }}
              />
            )}

            {imageUrl && (
              <div className="absolute inset-y-0 right-0 z-0 w-2/5 opacity-90 transition duration-500 group-hover:scale-105">
                <Image
                  src={imageUrl}
                  alt=""
                  fill
                  sizes="(max-width: 1024px) 40vw, 16vw"
                  className="object-contain object-right"
                />
              </div>
            )}

            <div className="relative z-10 flex h-full flex-col justify-between p-6">
              <div className="max-w-[70%]">
                <p className="text-xs font-semibold uppercase tracking-widest text-slate-700/80">
                  {promotion.eyebrow}
                </p>

                {promotion.title && (
                  <h2 className="mt-2 text-xl font-semibold leading-snug text-slate-950">
                    {promotion.title}
                  </h2>
                )}

                {promotion.description && (
                  <p className="mt-2 text-sm leading-relaxed text-slate-700/90">
                    {promotion.description}
                  </p>
                )}
              </div>

              <div className="mt-4">
                <Button
                  variant="secondary"
                  asChild
                  className="h-10 rounded-lg bg-white/90 px-4 text-sm font-semibold text-slate-900 shadow-sm transition hover:bg-white hover:shadow"
                >
                  <Link href={ctaHref}>
                    {promotion.cta}
                    <ChevronRightInline />
                  </Link>
                </Button>
              </div>
            </div>
          </article>
        );
      })}
    </div>
  );
}

function ChevronRightInline() {
  return (
    <span aria-hidden="true" className="ml-1.5">
      <svg
        width="16"
        height="16"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M9 18l6-6-6-6" />
      </svg>
    </span>
  );
}
