import { cn } from "@/lib/utils";

/**
 * Pure-SVG crop that visibly grows through five stages.
 * Colour comes from currentColor / semantic tokens so it themes correctly.
 */
export function CropArt({
  stage,
  health = 100,
  className,
  watering = false,
}: {
  stage: number;
  health?: number;
  className?: string;
  watering?: boolean;
}) {
  const wilted = health < 45;
  const ripe = stage >= 4;

  return (
    <div className={cn("relative aspect-square w-16 shrink-0 sm:w-20", className)}>
      {/* soil mound */}
      <svg viewBox="0 0 64 64" className="absolute inset-0 h-full w-full">
        <ellipse cx="32" cy="55" rx="22" ry="6" className="fill-accent/25" />
        <ellipse cx="32" cy="53" rx="16" ry="4" className="fill-accent/40" />
      </svg>

      <svg
        viewBox="0 0 64 64"
        className={cn(
          "absolute inset-0 h-full w-full crop-sway",
          ripe && "ripe-glow",
          wilted && "opacity-70 saturate-50",
        )}
        aria-hidden="true"
      >
        {stage === 0 && <circle cx="32" cy="50" r="3.5" className="fill-muted-foreground crop-pop" />}

        {stage >= 1 && (
          <g className="crop-pop">
            <path
              d={stage >= 3 ? "M32 52 L32 20" : stage === 2 ? "M32 52 L32 30" : "M32 52 L32 40"}
              className="stroke-primary"
              strokeWidth="3"
              strokeLinecap="round"
            />
            <path d="M32 42 C24 40 22 34 22 32 C28 32 31 36 32 42 Z" className="fill-primary/80" />
            {stage >= 2 && <path d="M32 36 C40 34 42 28 42 26 C36 26 33 30 32 36 Z" className="fill-primary/70" />}
            {stage >= 3 && <path d="M32 28 C24 26 22 20 22 18 C28 18 31 22 32 28 Z" className="fill-primary/60" />}
          </g>
        )}

        {stage >= 3 && (
          <g className="crop-pop">
            <circle cx="32" cy="18" r={stage >= 4 ? 7 : 4.5} className={ripe ? "fill-gold" : "fill-primary/50"} />
            {ripe && (
              <>
                <circle cx="23" cy="26" r="4" className="fill-gold/90" />
                <circle cx="41" cy="26" r="4" className="fill-gold/90" />
              </>
            )}
          </g>
        )}
      </svg>

      {watering && (
        <div className="pointer-events-none absolute inset-0">
          {[18, 32, 46].map((x, i) => (
            <span
              key={x}
              className="droplet absolute top-2 h-2 w-1 rounded-full bg-primary/70"
              style={{ left: `${x}%`, animationDelay: `${i * 0.12}s` }}
            />
          ))}
        </div>
      )}
    </div>
  );
}
