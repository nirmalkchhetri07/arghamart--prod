import { connection } from "next/server";
import { WholesaleGate } from "../_components/WholesaleGate";
import { WholesaleCartView } from "./WholesaleCartView";

// Ordering surface for authenticated wholesale members only — nothing here is
// usefully static (guests get a sign-in wall, members get personal carts), so
// opt into dynamic rendering. This also avoids HANGING_PROMISE_REJECTION noise
// at build time, where the gate's channel fetch outlives the static shell.
// (`export const dynamic` is not compatible with `cacheComponents`, so the
// `connection()` API is used instead.)

interface WholesaleCartPageProps {
  params: Promise<{ country: string; locale: string }>;
}

export default async function WholesaleCartPage({
  params,
}: WholesaleCartPageProps) {
  await connection();
  const { country, locale } = await params;
  return (
    <WholesaleGate basePath={`/${country}/${locale}`}>
      {() => <WholesaleCartView />}
    </WholesaleGate>
  );
}
