import unittest

from analyze_trace import TraceError, XMLRefs, choose_window, parse_events, parse_toc, summarize_cpu, summarize_events
import xml.etree.ElementTree as ET


class TraceAnalysisTests(unittest.TestCase):
    def test_toc_keeps_run_numbers_and_actual_platform(self):
        xml = """<trace-toc><run number="1"><info><target>
        <device platform="iOS Simulator" model="Simulated iPhone" os-version="27"/>
        <process name="App" pid="12"/></target><summary>
        <start-date>2026-10-12</start-date><duration>20</duration></summary></info>
        <data><table schema="time-profile"/></data></run>
        <run number="3"><info><target><device platform="iOS" model="iPhone" os-version="26"/>
        <process name="App" pid="34"/></target><summary><start-date>2026-10-15</start-date>
        <duration>40</duration></summary></info><data><table schema="os-log"/></data></run></trace-toc>"""
        runs = parse_toc(xml)
        self.assertEqual([run["run"] for run in runs], [1, 3])
        self.assertEqual(runs[0]["platform"], "iOS Simulator")
        self.assertEqual(runs[1]["platform"], "iOS")

    def test_tail_uses_recording_duration_including_idle_time(self):
        self.assertEqual(choose_window({"duration_seconds": 40}, [], tail=10), (30, 40))

    def test_marker_lead_in_includes_work_before_selection_callback(self):
        events = [{"name": "Activity.tab.selected", "kind": "event", "time_seconds": 10}]
        self.assertEqual(choose_window({"run": 2, "duration_seconds": 20}, events,
                                       marker="Activity.tab.selected", pre=0.5, duration=1), (9.5, 11))

    def test_repeated_marker_requires_an_explicit_occurrence(self):
        events = [{"name": "Search.request", "kind": "event", "time_seconds": time} for time in (4, 8)]
        run = {"run": 3, "duration_seconds": 20}
        with self.assertRaises(TraceError):
            choose_window(run, events, marker="Search.request")
        self.assertEqual(choose_window(run, events, marker="Search.request", occurrence=2), (8, 9))

    def test_missing_marker_does_not_become_a_zero_cost_result(self):
        with self.assertRaises(TraceError):
            choose_window({"run": 3, "duration_seconds": 20}, [], marker="Search.request")

    def test_zero_marker_occurrence_is_rejected(self):
        with self.assertRaises(TraceError):
            choose_window({"run": 2, "duration_seconds": 20}, [], marker="Search.request", occurrence=0)

    def test_empty_cpu_export_is_distinct_from_an_idle_window(self):
        empty = summarize_cpu("<result/>", 0, 1, "App", "12")
        self.assertFalse(empty["cpu_evidence_available"])
        self.assertIsNone(empty["main_sampled_ms"])
        self.assertEqual(empty["buckets"], [])
        populated = '<result><row><sample-time>2000000000</sample-time></row></result>'
        idle = summarize_cpu(populated, 0, 1, "App", "12")
        self.assertTrue(idle["cpu_evidence_available"])
        self.assertEqual(idle["main_sampled_ms"], 0)

    def test_log_references_and_formatted_nanoseconds_are_resolved(self):
        xml = """<result><row><event-time id="1">1000000000</event-time>
        <os-log-metadata id="2" fmt="PFT_PERF kind=end name=Activity.filter sequence=4 main=0 duration_ns=1.234.567 metadata=items=5000"/>
        </row><row><event-time ref="1"/><os-log-metadata ref="2"/></row></result>"""
        events = parse_events(xml)
        self.assertEqual(len(events), 2)
        self.assertEqual(events[1]["duration_ms"], 1.234567)
        self.assertEqual(events[1]["metadata"], "items=5000")

    def test_overlapping_interval_is_visible_even_if_it_started_before_window(self):
        events = [{"time_seconds": 9, "kind": "begin", "name": "Load", "sequence": "1", "main": "1", "metadata": "generation=2 items=5000"},
                  {"time_seconds": 11, "kind": "end", "name": "Load", "sequence": "1", "main": "0", "duration_ms": 2000}]
        result = summarize_events(events, 10, 12)
        self.assertEqual(result["overlapping_intervals"][0]["start_seconds"], 9)
        self.assertEqual(result["overlapping_intervals"][0]["duration_ms"], 2000)
        self.assertEqual(result["overlapping_intervals"][0]["begin_metadata"], "generation=2 items=5000")
        self.assertEqual(result["overlapping_intervals"][0]["end_metadata"], "")
        self.assertEqual(result["unfinished_intervals"], [])

    def test_cpu_weights_resolve_refs_keep_unknown_stacks_and_deduplicate_recursion(self):
        xml = """<result><row><sample-time>9000000000</sample-time>
        <thread id="1" fmt="Main Thread"><process id="2"><pid>12</pid></process></thread>
        <weight id="3">2000000</weight><tagged-backtrace id="4">
        <frame id="5" name="Layout"><binary id="6" name="SwiftUI"/></frame><frame ref="5"/>
        <frame name="$main"><binary name="App"/></frame></tagged-backtrace></row>
        <row><sample-time>9500000000</sample-time><thread ref="1"/><weight ref="3"/><sentinel/></row>
        <row><sample-time>10000000000</sample-time><thread ref="1"/><weight ref="3"/>
        <tagged-backtrace ref="4"/></row>
        <row><sample-time>9200000000</sample-time><thread fmt="worker"/><weight>9000000</weight></row>
        </result>"""
        cpu = summarize_cpu(xml, 9, 10, "App", "12", bucket=0.5)
        self.assertEqual(cpu["main_sampled_ms"], 4)
        self.assertEqual(cpu["samples_without_stack"], 1)
        self.assertEqual({item["frame"]: item["sampled_ms"] for item in cpu["inclusive_top"]},
                         {"Layout": 2, "$main": 2})
        self.assertEqual(cpu["nearest_app_top"], [{"frame": "$main", "sampled_ms": 2}])
        self.assertEqual([bucket["main_sampled_ms"] for bucket in cpu["buckets"]], [2, 2])

    def test_missing_reference_is_an_error_instead_of_silently_losing_samples(self):
        refs = XMLRefs(ET.fromstring('<result><thread ref="missing"/></result>'))
        with self.assertRaises(TraceError):
            refs.resolve(ET.fromstring('<thread ref="missing"/>'))


if __name__ == "__main__":
    unittest.main()
