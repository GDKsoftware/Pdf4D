// Reference hashes for the stroker and dash tests of the Delphi port (TestRustReference* in Pdf4D.Render.Native.Stroker.Tests and
// Pdf4D.Render.Native.Dash.Tests). Each case builds the same path as the Delphi test, strokes or dashes it with tiny-skia and hashes
// the result with FNV-1a over the verbs and the bits of the points, as PathHash does in the tests.
use tiny_skia_path::{LineCap, LineJoin, Path, PathBuilder, Stroke, StrokeDash};

fn closed_path() -> Path {
    let mut pb = PathBuilder::new();
    pb.move_to(10.0, 10.0);
    pb.quad_to(50.0, 100.0, 90.0, 10.0);
    pb.cubic_to(120.0, 80.0, 150.0, -60.0, 190.0, 10.0);
    pb.line_to(150.0, 60.0);
    pb.close();
    pb.finish().unwrap()
}

fn open_path() -> Path {
    let mut pb = PathBuilder::new();
    pb.move_to(10.0, 10.0);
    pb.quad_to(50.0, 100.0, 90.0, 10.0);
    pb.cubic_to(120.0, 80.0, 150.0, -60.0, 190.0, 10.0);
    pb.line_to(150.0, 60.0);
    pb.line_to(150.0, 60.0);
    pb.move_to(5.0, 5.0);
    pb.line_to(5.0, 5.0);
    pb.move_to(30.0, 30.0);
    pb.cubic_to(80.0, 30.0, 10.0, 30.0, 60.0, 30.0);
    pb.move_to(70.0, 70.0);
    pb.cubic_to(120.0, 120.0, 20.0, 120.0, 70.0, 70.0);
    pb.finish().unwrap()
}

fn path_hash(path: &Path) -> u32 {
    let mut hash: u32 = 2166136261;
    for verb in path.verbs() {
        hash = (hash ^ (*verb as u32)).wrapping_mul(16777619);
    }
    for pt in path.points() {
        hash = (hash ^ pt.x.to_bits()).wrapping_mul(16777619);
        hash = (hash ^ pt.y.to_bits()).wrapping_mul(16777619);
    }
    hash
}

fn stroke_case(name: &str, path: &Path, width: f32, miter_limit: f32, res_scale: f32, join: LineJoin, cap: LineCap, expected: u32) -> bool {
    let mut stroke = Stroke::default();
    stroke.width = width;
    stroke.miter_limit = miter_limit;
    stroke.line_join = join;
    stroke.line_cap = cap;
    report(name, path.stroke(&stroke, res_scale), expected)
}

fn dash_case(name: &str, path: &Path, intervals: Vec<f32>, offset: f32, res_scale: f32, expected: u32) -> bool {
    let dash = StrokeDash::new(intervals, offset).unwrap();
    report(name, path.dash(&dash, res_scale), expected)
}

fn report(name: &str, result: Option<Path>, expected: u32) -> bool {
    let hash = path_hash(&result.expect("tiny-skia returned no path"));
    let verdict = if hash == expected { "matches" } else { "DIFFERS" };
    println!("{:<52} ${:08X}  {} the Delphi test (${:08X})", name, hash, verdict, expected);
    hash == expected
}

fn main() {
    let closed = closed_path();
    let open = open_path();

    // The expected values are the ones pinned in the Delphi tests
    let results = [
        stroke_case("stroker closed round join, round cap", &closed, 6.0, 4.0, 1.0, LineJoin::Round, LineCap::Round, 0xB33489F2),
        stroke_case("stroker closed scaled miter clip, square cap", &closed, 6.0, 4.0, 3.5, LineJoin::MiterClip, LineCap::Square, 0x1659CDFA),
        stroke_case("stroker open miter, square cap", &open, 9.0, 2.5, 1.0, LineJoin::Miter, LineCap::Square, 0x65C7A748),
        stroke_case("stroker open miter clip, round cap", &open, 9.0, 2.5, 1.0, LineJoin::MiterClip, LineCap::Round, 0x8A7D9140),
        stroke_case("stroker open round join, butt cap", &open, 9.0, 2.5, 1.0, LineJoin::Round, LineCap::Butt, 0x40408ED3),
        stroke_case("stroker open bevel, square cap", &open, 9.0, 2.5, 1.0, LineJoin::Bevel, LineCap::Square, 0x764E3CE6),
        dash_case("dash open path with offset", &open, vec![5.0, 2.0, 1.0, 2.0], 4.5, 1.0, 0x710C208A),
        dash_case("dash closed path with offset", &closed, vec![5.0, 2.0, 1.0, 2.0], 4.5, 2.0, 0x691AE21E),
        dash_case("dash zero-length dashes, negative offset", &open, vec![0.0, 6.0], -2.0, 1.0, 0x63F1A85E),
        dash_case("dash closed path with curves", &closed, vec![7.0, 3.0], 0.0, 2.0, 0xF8F74028),
    ];

    if results.iter().any(|ok| !ok) {
        std::process::exit(1);
    }
}
