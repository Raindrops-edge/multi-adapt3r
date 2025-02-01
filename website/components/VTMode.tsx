export default function VTMode({
  value,
  ansi = false,
}: {
  value: number;
  ansi: boolean;
}) {
  return (
    <div className="flex my-2.5">
      <div className="border px-1 grid grid-rows-2 grid-cols-1 text-center">
        <div>
          {ansi ? "" : "?"}
          {value}
        </div>
      </div>
    </div>
  );
}
