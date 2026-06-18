import Foundation

/// Builds the HTML/CSS/JS rendered inside the WebView.
///
/// The Swift side ships a `GraphData` JSON blob plus a self-contained script that
/// draws the commit graph as SVG and the commit list beside it — no CDN, fully
/// offline. Theming reuses MarkdownRender's CSS-variable palette so the two tools
/// look like siblings in both light and dark mode.
struct HTMLGenerator {

    /// Main view: the graph + commit list, with a slide-in detail panel.
    static func generateHTML(graphJSON: String, theme: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>git-graph</title>
            <style>
        \(generateCSS())
            </style>
        </head>
        <body>
            <div id="graph-root"></div>

            <!-- Slide-in commit detail panel -->
            <aside id="detail-panel" class="detail-panel">
                <button class="detail-close" id="detail-close" aria-label="Close">&times;</button>
                <div id="detail-content"></div>
            </aside>
            <div id="detail-backdrop" class="detail-backdrop"></div>

            <script>
                const GRAPH_DATA = \(graphJSON);
            </script>
            <script>
        \(generateJS())
            </script>
        </body>
        </html>
        """
    }

    // MARK: - CSS

    static func generateCSS() -> String {
        // Palette + base styling mirror MarkdownRender's HTMLGenerator.generateCSS().
        return """
        :root {
            --bg-color: #ffffff;
            --text-color: #24292f;
            --text-secondary: #57606a;
            --border-color: #d0d7de;
            --code-bg: #f6f8fa;
            --link-color: #0969da;
            --row-hover: #f6f8fa;
            --row-selected: #ddf4ff;
            --pill-bg: #eaeef2;
            --shadow: rgba(31, 35, 40, 0.15);
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --bg-color: #0d1117;
                --text-color: #c9d1d9;
                --text-secondary: #8b949e;
                --border-color: #30363d;
                --code-bg: #161b22;
                --link-color: #58a6ff;
                --row-hover: #161b22;
                --row-selected: #173a5e;
                --pill-bg: #21262d;
                --shadow: rgba(1, 4, 9, 0.6);
            }
        }

        /* Lane palette — 8 distinct, color-blind-friendly-ish hues. JS references
           these by index via var(--lane-N). */
        :root {
            --lane-0: #0969da; /* blue   */
            --lane-1: #1a7f37; /* green  */
            --lane-2: #bf3989; /* magenta*/
            --lane-3: #bc4c00; /* orange */
            --lane-4: #8250df; /* purple */
            --lane-5: #1b7c83; /* teal   */
            --lane-6: #9a6700; /* gold   */
            --lane-7: #cf222e; /* red    */
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --lane-0: #58a6ff;
                --lane-1: #3fb950;
                --lane-2: #db61a2;
                --lane-3: #f0883e;
                --lane-4: #a371f7;
                --lane-5: #39c5cf;
                --lane-6: #d29922;
                --lane-7: #f85149;
            }
        }

        * { box-sizing: border-box; }

        html {
            font-size: 14px;
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif;
            color: var(--text-color);
            background-color: var(--bg-color);
            margin: 0;
            padding: 0;
        }

        /* The graph is a list of rows; each row has an SVG cell on the left and
           commit text on the right. The SVG cells stack to form continuous lanes. */
        #graph-root {
            padding: 8px 0 64px;
        }

        .commit-row {
            display: flex;
            align-items: stretch;
            cursor: pointer;
            border-left: 3px solid transparent;
        }

        .commit-row:hover {
            background-color: var(--row-hover);
        }

        .commit-row.selected {
            background-color: var(--row-selected);
            border-left-color: var(--link-color);
        }

        .commit-row.dimmed {
            opacity: 0.28;
        }

        .commit-row.match {
            background-color: var(--row-hover);
        }

        .row-graph {
            flex: 0 0 auto;
            position: relative;
        }

        .row-graph svg { display: block; }

        .row-info {
            flex: 1 1 auto;
            min-width: 0;
            padding: 7px 16px 7px 4px;
            display: flex;
            align-items: baseline;
            gap: 10px;
            border-bottom: 1px solid transparent;
        }

        .row-subject {
            flex: 1 1 auto;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            font-weight: 500;
        }

        .row-meta {
            flex: 0 0 auto;
            color: var(--text-secondary);
            font-size: 0.85rem;
            display: flex;
            gap: 14px;
            align-items: baseline;
        }

        .row-hash {
            font-family: "SF Mono", SFMono-Regular, ui-monospace, Menlo, monospace;
            font-size: 0.8rem;
        }

        .row-author { max-width: 160px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        /* The author name is clickable: it opens the author-activity panel. */
        .row-author { cursor: pointer; border-radius: 4px; padding: 0 3px; margin: 0 -3px; }
        .row-author:hover { color: var(--link-color); background: var(--pill-bg); }

        /* Ref pills (branches, tags, HEAD) shown before the subject. */
        .ref-pill {
            flex: 0 0 auto;
            font-size: 0.72rem;
            font-weight: 600;
            padding: 1px 8px;
            border-radius: 20px;
            background: var(--pill-bg);
            color: var(--text-color);
            white-space: nowrap;
            line-height: 1.6;
            border: 1px solid var(--border-color);
        }
        .ref-pill.head      { background: var(--link-color); color: #fff; border-color: transparent; }
        .ref-pill.tag       { background: var(--lane-6); color: #fff; border-color: transparent; }
        .ref-pill.remote    { opacity: 0.85; font-style: italic; }
        .ref-pill::before   { content: ""; }
        .ref-pill.tag::before { content: "⌖ "; }

        /* Header bar */
        .header {
            position: sticky;
            top: 0;
            z-index: 5;
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 10px 16px;
            background: var(--bg-color);
            border-bottom: 1px solid var(--border-color);
        }
        .header .repo-name { font-weight: 700; font-size: 1.05rem; }
        .header .count { color: var(--text-secondary); font-size: 0.85rem; }
        .header .spacer { flex: 1 1 auto; }

        /* Tooltip on node hover */
        #tooltip {
            position: fixed;
            z-index: 50;
            pointer-events: none;
            background: var(--text-color);
            color: var(--bg-color);
            padding: 6px 10px;
            border-radius: 6px;
            font-size: 0.8rem;
            max-width: 360px;
            box-shadow: 0 4px 14px var(--shadow);
            opacity: 0;
            transition: opacity 0.1s ease;
        }
        #tooltip .tt-subject { font-weight: 600; margin-bottom: 2px; }
        #tooltip .tt-meta { opacity: 0.8; font-size: 0.74rem; }

        /* Detail panel */
        .detail-panel {
            position: fixed;
            top: 0;
            right: 0;
            bottom: 0;
            width: min(560px, 80vw);
            background: var(--bg-color);
            border-left: 1px solid var(--border-color);
            box-shadow: -8px 0 24px var(--shadow);
            transform: translateX(100%);
            transition: transform 0.22s cubic-bezier(0.2, 0.7, 0.2, 1);
            z-index: 40;
            overflow-y: auto;
            padding: 24px;
        }
        .detail-panel.open { transform: translateX(0); }

        .detail-backdrop {
            position: fixed;
            inset: 0;
            background: rgba(0,0,0,0.18);
            opacity: 0;
            pointer-events: none;
            transition: opacity 0.22s ease;
            z-index: 39;
        }
        .detail-backdrop.open { opacity: 1; pointer-events: auto; }

        .detail-close {
            position: absolute;
            top: 12px;
            right: 16px;
            background: none;
            border: none;
            font-size: 26px;
            line-height: 1;
            color: var(--text-secondary);
            cursor: pointer;
            padding: 2px 8px;
            border-radius: 6px;
        }
        .detail-close:hover { background: var(--code-bg); color: var(--text-color); }

        .detail-subject { font-size: 1.2rem; font-weight: 600; margin: 0 32px 12px 0; line-height: 1.3; }
        .detail-table { font-size: 0.85rem; color: var(--text-secondary); margin-bottom: 16px; line-height: 1.7; }
        .detail-table .mono { font-family: "SF Mono", SFMono-Regular, ui-monospace, Menlo, monospace; color: var(--text-color); }
        .detail-body {
            white-space: pre-wrap;
            background: var(--code-bg);
            border-radius: 8px;
            padding: 14px 16px;
            margin-bottom: 18px;
            font-size: 0.9rem;
            line-height: 1.5;
        }
        .detail-diff {
            font-family: "SF Mono", SFMono-Regular, ui-monospace, Menlo, monospace;
            font-size: 0.78rem;
            line-height: 1.45;
            white-space: pre;
            overflow-x: auto;
            background: var(--code-bg);
            border-radius: 8px;
            padding: 14px 16px;
        }
        .detail-diff .add { color: var(--lane-1); }
        .detail-diff .del { color: var(--lane-7); }
        .detail-diff .hunk { color: var(--link-color); }
        .detail-diff .meta { color: var(--text-secondary); font-weight: 600; }
        .detail-loading { color: var(--text-secondary); font-style: italic; }
        .detail-section-title { font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-secondary); margin: 18px 0 8px; font-weight: 600; }

        /* Author-activity panel */
        .author-head { display: flex; align-items: center; gap: 12px; margin: 0 32px 4px 0; }
        .author-avatar {
            flex: 0 0 auto;
            width: 40px; height: 40px;
            border-radius: 50%;
            display: flex; align-items: center; justify-content: center;
            color: #fff; font-weight: 700; font-size: 1.1rem;
            text-transform: uppercase;
        }
        .author-name { font-size: 1.2rem; font-weight: 600; line-height: 1.2; }
        .author-email { font-size: 0.82rem; color: var(--text-secondary); }

        /* Stat cards: commit count, active days, date span. */
        .stat-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin: 16px 0 4px; }
        .stat-card { background: var(--code-bg); border: 1px solid var(--border-color); border-radius: 8px; padding: 12px 14px; }
        .stat-value { font-size: 1.4rem; font-weight: 700; line-height: 1.1; }
        .stat-label { font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.03em; color: var(--text-secondary); margin-top: 4px; }
        .stat-share { font-size: 0.82rem; color: var(--text-secondary); margin-top: 10px; }

        /* Activity timeline — a row of bars, one per bucket (week or day). */
        .timeline { display: flex; align-items: flex-end; gap: 2px; height: 72px; margin: 6px 0 2px; }
        .timeline-bar {
            flex: 1 1 0;
            min-width: 2px;
            background: var(--link-color);
            border-radius: 2px 2px 0 0;
            min-height: 2px;
            opacity: 0.85;
            transition: opacity 0.1s ease;
        }
        .timeline-bar:hover { opacity: 1; }
        .timeline-bar.empty { background: var(--border-color); opacity: 0.5; }
        .timeline-axis { display: flex; justify-content: space-between; font-size: 0.72rem; color: var(--text-secondary); margin-top: 2px; }

        /* This author's commits — compact, clickable rows reusing the diff panel. */
        .author-commit {
            display: flex; align-items: baseline; gap: 10px;
            padding: 6px 8px; border-radius: 6px; cursor: pointer;
            border-bottom: 1px solid transparent;
        }
        .author-commit:hover { background: var(--row-hover); }
        .author-commit .ac-subject { flex: 1 1 auto; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .author-commit .ac-when { flex: 0 0 auto; color: var(--text-secondary); font-size: 0.8rem; }
        .author-commit .ac-hash { flex: 0 0 auto; font-family: "SF Mono", SFMono-Regular, ui-monospace, Menlo, monospace; font-size: 0.76rem; color: var(--text-secondary); }

        /* Search bar (mirrors MarkdownRender's slide-down find bar) */
        #search-bar {
            position: fixed;
            top: -48px;
            left: 0;
            right: 0;
            height: 48px;
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 0 16px;
            background: var(--bg-color);
            border-bottom: 1px solid var(--border-color);
            box-shadow: 0 2px 8px var(--shadow);
            transition: top 0.2s ease;
            z-index: 60;
        }
        #search-bar.open { top: 0; }
        #search-input {
            flex: 0 0 320px;
            font-size: 0.95rem;
            padding: 6px 10px;
            border: 1px solid var(--border-color);
            border-radius: 6px;
            background: var(--code-bg);
            color: var(--text-color);
        }
        #search-input:focus { outline: 2px solid var(--link-color); outline-offset: -1px; }
        #search-count { color: var(--text-secondary); font-size: 0.85rem; }
        #search-bar button {
            background: var(--code-bg);
            border: 1px solid var(--border-color);
            border-radius: 6px;
            color: var(--text-color);
            padding: 5px 12px;
            cursor: pointer;
            font-size: 0.85rem;
        }
        #search-bar button:hover { background: var(--pill-bg); }

        .empty-state {
            text-align: center;
            padding: 80px 24px;
            color: var(--text-secondary);
        }
        .empty-state .icon { font-size: 48px; margin-bottom: 12px; }
        """
    }

    // MARK: - JS

    static func generateJS() -> String {
        // Drawing constants kept here so layout math lives in one place.
        return """
        (function () {
            const LANE_W = 18;     // horizontal px between lanes
            const ROW_H = 28;      // px per commit row
            const DOT_R = 5;       // node radius
            const PAD_X = 14;      // left padding inside the graph column

            const data = GRAPH_DATA;
            const commits = data.commits;
            const byHash = {};
            commits.forEach((c, i) => { byHash[c.hash] = i; });

            const root = document.getElementById('graph-root');

            function laneColor(idx) { return 'var(--lane-' + (idx % 8) + ')'; }
            function laneX(lane) { return PAD_X + lane * LANE_W; }

            // ---- Empty repo ----
            if (!commits.length) {
                root.innerHTML =
                    '<div class="empty-state"><div class="icon">🌱</div>' +
                    '<h2>No commits yet</h2>' +
                    '<p>This repository doesn\\'t have any commits to show.</p></div>';
                return;
            }

            const graphWidth = laneX(data.totalLanes) + PAD_X;

            // ---- Header ----
            const header = document.createElement('div');
            header.className = 'header';
            const countText = data.truncated
                ? ('showing ' + data.shownCount.toLocaleString() + ' of ' + data.totalCount.toLocaleString() + ' commits')
                : (data.totalCount.toLocaleString() + ' commit' + (data.totalCount === 1 ? '' : 's'));
            header.innerHTML =
                '<span class="repo-name">' + escapeHTML(data.repoName) + '</span>' +
                '<span class="count">' + countText + '</span>' +
                '<span class="spacer"></span>' +
                '<span class="count">⌘F search · ⌘R reload</span>';
            root.appendChild(header);

            // ---- Rows ----
            // To draw lanes that pass *through* a row (a branch that doesn't have a
            // commit on this row but is still active), we precompute, for each row,
            // which lanes are "passing through" by looking at edges that span rows.
            // Simpler robust approach: each row's SVG draws (a) its own node, and
            // (b) for every parent, a line from this node down to the parent's row.
            // Lines are drawn per-row as segments so they tile correctly. We render
            // all edges in an absolutely-positioned full-height SVG overlay instead,
            // which avoids per-row clipping headaches.

            const list = document.createElement('div');
            list.style.position = 'relative';
            root.appendChild(list);

            // Full-height overlay SVG for edges (drawn behind the rows' nodes).
            const totalHeight = commits.length * ROW_H;
            const svgNS = 'http://www.w3.org/2000/svg';
            const edgeSvg = document.createElementNS(svgNS, 'svg');
            edgeSvg.setAttribute('width', graphWidth);
            edgeSvg.setAttribute('height', totalHeight);
            edgeSvg.style.position = 'absolute';
            edgeSvg.style.left = '0';
            edgeSvg.style.top = '0';
            edgeSvg.style.pointerEvents = 'none';
            list.appendChild(edgeSvg);

            function rowY(index) { return index * ROW_H + ROW_H / 2; }

            // Draw an edge from a commit (childIndex, childLane) down to its parent
            // (parentIndex) terminating in parentLane. Curve near the endpoints when
            // lanes differ so merges/branches look smooth.
            function drawEdge(childIndex, childLane, parentIndex, parentLane, colorIdx) {
                const x1 = laneX(childLane), y1 = rowY(childIndex);
                const x2 = laneX(parentLane), y2 = rowY(parentIndex);
                const path = document.createElementNS(svgNS, 'path');
                let d;
                if (childLane === parentLane) {
                    d = 'M ' + x1 + ' ' + y1 + ' L ' + x2 + ' ' + y2;
                } else {
                    // S-curve: leave the child vertically, bend into the parent lane.
                    const midY = y1 + (y2 - y1) * 0.5;
                    d = 'M ' + x1 + ' ' + y1 +
                        ' C ' + x1 + ' ' + midY + ', ' + x2 + ' ' + midY + ', ' + x2 + ' ' + y2;
                }
                path.setAttribute('d', d);
                path.setAttribute('fill', 'none');
                path.setAttribute('stroke', laneColor(colorIdx));
                path.setAttribute('stroke-width', '2');
                path.setAttribute('stroke-linecap', 'round');
                edgeSvg.appendChild(path);
            }

            // Edges first (so nodes sit on top).
            commits.forEach((c, i) => {
                c.parents.forEach((p, pi) => {
                    const parentIndex = byHash[p];
                    const parentLane = (c.parentLanes && c.parentLanes[pi] != null) ? c.parentLanes[pi] : c.lane;
                    if (parentIndex === undefined) {
                        // Parent not loaded (history capped): draw a short stub fading down.
                        const stub = document.createElementNS(svgNS, 'path');
                        const x = laneX(parentLane), y = rowY(i);
                        stub.setAttribute('d', 'M ' + x + ' ' + y + ' L ' + x + ' ' + (y + ROW_H * 0.7));
                        stub.setAttribute('stroke', laneColor(c.color));
                        stub.setAttribute('stroke-width', '2');
                        stub.setAttribute('stroke-dasharray', '2 3');
                        stub.setAttribute('fill', 'none');
                        edgeSvg.appendChild(stub);
                        return;
                    }
                    // Color the edge by the parent lane's owning commit color when
                    // branching, else the child's color — keeps a branch one hue.
                    const colorIdx = (pi === 0) ? c.color : (commits[parentIndex] ? commits[parentIndex].color : c.color);
                    drawEdge(i, c.lane, parentIndex, parentLane, colorIdx);
                });
            });

            // Then the nodes + the clickable rows.
            commits.forEach((c, i) => {
                const row = document.createElement('div');
                row.className = 'commit-row';
                row.dataset.index = i;
                row.dataset.hash = c.hash;
                row.style.height = ROW_H + 'px';

                // Graph cell (just the node circle; edges are in the overlay).
                const gcell = document.createElement('div');
                gcell.className = 'row-graph';
                gcell.style.width = graphWidth + 'px';
                gcell.style.height = ROW_H + 'px';

                const nodeSvg = document.createElementNS(svgNS, 'svg');
                nodeSvg.setAttribute('width', graphWidth);
                nodeSvg.setAttribute('height', ROW_H);
                const circle = document.createElementNS(svgNS, 'circle');
                circle.setAttribute('cx', laneX(c.lane));
                circle.setAttribute('cy', ROW_H / 2);
                circle.setAttribute('r', c.parents.length > 1 ? DOT_R + 1 : DOT_R);
                circle.setAttribute('fill', laneColor(c.color));
                circle.setAttribute('stroke', 'var(--bg-color)');
                circle.setAttribute('stroke-width', '1.5');
                nodeSvg.appendChild(circle);
                gcell.appendChild(nodeSvg);
                row.appendChild(gcell);

                // Info cell.
                const info = document.createElement('div');
                info.className = 'row-info';

                let pills = '';
                (c.refs || []).forEach(r => {
                    let cls = 'ref-pill';
                    if (r.kind === 'head') cls += ' head';
                    else if (r.kind === 'tag') cls += ' tag';
                    else if (r.kind === 'remoteBranch') cls += ' remote';
                    pills += '<span class="' + cls + '">' + escapeHTML(r.name) + '</span>';
                });

                info.innerHTML =
                    pills +
                    '<span class="row-subject">' + escapeHTML(c.subject) + '</span>' +
                    '<span class="row-meta">' +
                        '<span class="row-author" title="See ' + escapeHTML(c.authorName) + '\\u2019s activity">' + escapeHTML(c.authorName) + '</span>' +
                        '<span>' + relativeTime(c.timestamp) + '</span>' +
                        '<span class="row-hash">' + escapeHTML(c.shortHash) + '</span>' +
                    '</span>';
                row.appendChild(info);

                // Interactions. Clicking the author name opens the author panel
                // (and is stopped from also opening the commit detail below it).
                const authorEl = info.querySelector('.row-author');
                authorEl.addEventListener('click', (e) => {
                    e.stopPropagation();
                    openAuthor(c.authorEmail, c.authorName);
                });
                row.addEventListener('click', () => openDetail(i));
                row.addEventListener('mouseenter', (e) => showTooltip(e, c));
                row.addEventListener('mousemove', moveTooltip);
                row.addEventListener('mouseleave', hideTooltip);

                list.appendChild(row);
            });

            // ---- Tooltip ----
            const tooltip = document.createElement('div');
            tooltip.id = 'tooltip';
            document.body.appendChild(tooltip);
            function showTooltip(e, c) {
                tooltip.innerHTML =
                    '<div class="tt-subject">' + escapeHTML(c.subject) + '</div>' +
                    '<div class="tt-meta">' + escapeHTML(c.shortHash) + ' · ' + escapeHTML(c.authorName) + '</div>';
                tooltip.style.opacity = '1';
                moveTooltip(e);
            }
            function moveTooltip(e) {
                const x = Math.min(e.clientX + 14, window.innerWidth - 380);
                const y = Math.min(e.clientY + 16, window.innerHeight - 60);
                tooltip.style.left = x + 'px';
                tooltip.style.top = y + 'px';
            }
            function hideTooltip() { tooltip.style.opacity = '0'; }

            // ---- Detail panel ----
            const panel = document.getElementById('detail-panel');
            const backdrop = document.getElementById('detail-backdrop');
            const content = document.getElementById('detail-content');
            let selectedRow = null;

            document.getElementById('detail-close').addEventListener('click', closeDetail);
            backdrop.addEventListener('click', closeDetail);

            function openDetail(index) {
                const c = commits[index];
                if (selectedRow) selectedRow.classList.remove('selected');
                selectedRow = list.querySelector('.commit-row[data-index="' + index + '"]');
                if (selectedRow) selectedRow.classList.add('selected');

                const date = new Date(c.timestamp * 1000);
                let refsHTML = '';
                (c.refs || []).forEach(r => {
                    let cls = 'ref-pill';
                    if (r.kind === 'head') cls += ' head';
                    else if (r.kind === 'tag') cls += ' tag';
                    else if (r.kind === 'remoteBranch') cls += ' remote';
                    refsHTML += '<span class="' + cls + '">' + escapeHTML(r.name) + '</span> ';
                });

                content.innerHTML =
                    '<div class="detail-subject">' + escapeHTML(c.subject) + '</div>' +
                    (refsHTML ? '<div style="margin-bottom:12px">' + refsHTML + '</div>' : '') +
                    '<div class="detail-table">' +
                        '<div><span class="mono">' + escapeHTML(c.hash) + '</span></div>' +
                        '<div>' + escapeHTML(c.authorName) + ' &lt;' + escapeHTML(c.authorEmail) + '&gt;</div>' +
                        '<div>' + date.toLocaleString() + '</div>' +
                        (c.parents.length ? '<div>parents: <span class="mono">' +
                            c.parents.map(p => escapeHTML(p.substring(0, 7))).join(', ') + '</span></div>' : '<div>root commit</div>') +
                    '</div>' +
                    (c.body ? '<div class="detail-body">' + escapeHTML(c.body) + '</div>' : '') +
                    '<div class="detail-section-title">Changes</div>' +
                    '<div class="detail-loading" id="diff-slot">Loading diff…</div>';

                panel.classList.add('open');
                backdrop.classList.add('open');

                // Ask the native side for the diff (lazy).
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commit) {
                    window.webkit.messageHandlers.commit.postMessage(c.hash);
                } else {
                    const slot = document.getElementById('diff-slot');
                    if (slot) { slot.textContent = '(diff unavailable in this context)'; }
                }
            }

            function closeDetail() {
                panel.classList.remove('open');
                backdrop.classList.remove('open');
                if (selectedRow) { selectedRow.classList.remove('selected'); selectedRow = null; }
            }

            // ---- Author activity panel ----
            // Reuses the same slide-in panel. The report is fetched lazily from
            // the native side, scoped to the date window of the commits currently
            // loaded in the graph — so it answers "what has this author done in
            // the range I'm looking at". Within that window it uses `--all` (so it
            // catches their real feature-branch work, not just the merge commits
            // that land on HEAD) with `--no-merges` (so merge clicks don't inflate
            // the counts; merges in the window are reported separately).

            // The loaded graph's time bounds (Unix seconds), sent with each query
            // so the report matches the visible range. The list is --topo-order,
            // not strictly time-sorted, so take the actual min/max rather than the
            // first/last element.
            let loadedSince = Infinity, loadedUntil = 0;
            commits.forEach(c => {
                if (c.timestamp < loadedSince) loadedSince = c.timestamp;
                if (c.timestamp > loadedUntil) loadedUntil = c.timestamp;
            });
            if (!commits.length) { loadedSince = 0; loadedUntil = 0; }
            // If the graph isn't capped, it reaches the repo root — don't impose a
            // lower bound, so the very first commits aren't excluded by rounding.
            const sinceBound = data.truncated ? loadedSince : null;

            // Eight palette hues, used to give each author a stable avatar color.
            function colorForKey(key) {
                let h = 0;
                for (let i = 0; i < key.length; i++) { h = (h * 31 + key.charCodeAt(i)) >>> 0; }
                return laneColor(h % 8);
            }

            // Remember the last-clicked identity so a late async reply that no
            // longer matches the open panel is ignored.
            let pendingAuthorEmail = null;

            function openAuthor(email, name) {
                email = (email || '').trim();
                name = name || email;

                // Clear any commit-row selection — this is an author view, not a commit.
                if (selectedRow) { selectedRow.classList.remove('selected'); selectedRow = null; }

                const accent = colorForKey((email || name).toLowerCase());
                const initials = (name || email || '?').trim().charAt(0);

                // Open immediately with a header + loading state; the stats/commits
                // arrive from Swift via renderAuthor().
                content.innerHTML =
                    '<div class="author-head">' +
                        '<div class="author-avatar" style="background:' + accent + '">' + escapeHTML(initials) + '</div>' +
                        '<div>' +
                            '<div class="author-name">' + escapeHTML(name) + '</div>' +
                            (email ? '<div class="author-email">' + escapeHTML(email) + '</div>' : '') +
                        '</div>' +
                    '</div>' +
                    '<div class="detail-loading" id="author-slot">Loading activity…</div>';

                panel.classList.add('open');
                backdrop.classList.add('open');

                // Without an email we can't run the repo-wide query reliably.
                if (!email) {
                    const slot = document.getElementById('author-slot');
                    if (slot) slot.textContent = 'No email recorded for this author.';
                    return;
                }

                pendingAuthorEmail = email.toLowerCase();
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.author) {
                    window.webkit.messageHandlers.author.postMessage({
                        email: email,
                        since: sinceBound,
                        until: loadedUntil
                    });
                } else {
                    const slot = document.getElementById('author-slot');
                    if (slot) slot.textContent = '(author activity unavailable in this context)';
                }
            }

            // Called by Swift once `git log --all` returns. `report` is an
            // AuthorActivity JSON object, or null if the query failed.
            window.renderAuthor = function (email, report) {
                // Ignore stale replies (user clicked a different author since).
                if (!email || email.toLowerCase() !== pendingAuthorEmail) return;
                const slot = document.getElementById('author-slot');
                if (!slot) return;

                if (!report || !report.commits || !report.commits.length) {
                    slot.className = 'detail-loading';
                    slot.textContent = report && report.mergeCount
                        ? 'Only merge commits in this range (' + report.mergeCount + ' merge' +
                          (report.mergeCount === 1 ? '' : 's') + ' landed, no authored commits).'
                        : 'No commits by this author in the loaded range.';
                    return;
                }

                const mine = report.commits;               // newest-first, no merges
                const times = mine.map(c => c.timestamp);
                const firstT = Math.min.apply(null, times);
                const lastT  = Math.max.apply(null, times);
                const days = new Set(mine.map(c => new Date(c.timestamp * 1000).toDateString()));

                let html =
                    '<div class="stat-grid">' +
                        statCard(mine.length.toLocaleString(), 'commit' + (mine.length === 1 ? '' : 's')) +
                        statCard(days.size.toLocaleString(), 'active day' + (days.size === 1 ? '' : 's')) +
                        statCard(spanLabel(firstT, lastT), 'span') +
                    '</div>' +
                    '<div class="stat-share">in the loaded range · first ' +
                        new Date(firstT * 1000).toLocaleDateString() +
                        ' · latest ' + new Date(lastT * 1000).toLocaleDateString() +
                        (report.mergeCount ? ' · ' + report.mergeCount.toLocaleString() +
                            ' merge' + (report.mergeCount === 1 ? '' : 's') + ' landed' : '') +
                    '</div>';

                // ---- Timeline ----
                // Span the loaded graph window (not just the author's first/last
                // commit) so the bars sit where this author's activity falls within
                // the visible range, and quiet stretches read as gaps.
                const tlSince = (loadedSince && loadedSince <= firstT) ? loadedSince : firstT;
                const tlUntil = (loadedUntil && loadedUntil >= lastT) ? loadedUntil : lastT;
                html += '<div class="detail-section-title">Activity</div>' + buildTimeline(times, tlSince, tlUntil);

                // ---- This author's commits ----
                html += '<div class="detail-section-title">Commits (' + mine.length.toLocaleString() + ')</div>';
                html += '<div id="author-commits">';
                mine.forEach(c => {
                    html +=
                        '<div class="author-commit" data-hash="' + escapeHTML(c.hash) + '">' +
                            '<span class="ac-subject">' + escapeHTML(c.subject) + '</span>' +
                            '<span class="ac-when">' + relativeTime(c.timestamp) + '</span>' +
                            '<span class="ac-hash">' + escapeHTML(c.shortHash) + '</span>' +
                        '</div>';
                });
                html += '</div>';

                slot.className = '';
                slot.innerHTML = html;

                // Clicking one of the author's commits jumps to its full detail —
                // but only if that commit is actually loaded in the graph (repo-wide
                // results can include commits outside the loaded window).
                slot.querySelectorAll('.author-commit').forEach(el => {
                    const idx = byHash[el.dataset.hash];
                    if (idx === undefined) {
                        el.style.cursor = 'default';
                        el.title = 'Not in the loaded graph';
                        return;
                    }
                    el.addEventListener('click', () => openDetail(idx));
                });
            };

            function statCard(value, label) {
                return '<div class="stat-card"><div class="stat-value">' + escapeHTML(String(value)) +
                    '</div><div class="stat-label">' + escapeHTML(label) + '</div></div>';
            }

            // A compact human label for the time between first and last commit.
            function spanLabel(firstT, lastT) {
                const secs = Math.max(0, lastT - firstT);
                if (secs < 86400) return '1 day';
                const units = [['yr', 31536000], ['mo', 2592000], ['wk', 604800], ['day', 86400]];
                for (const [name, u] of units) {
                    const v = Math.floor(secs / u);
                    if (v >= 1) return v + ' ' + name + (v === 1 ? '' : 's');
                }
                return '1 day';
            }

            // Bucket the author's commit times into ~24 bars spanning their own
            // first→latest range, so the shape shows when they were active and
            // their gaps are visible.
            function buildTimeline(times, lo, hi) {
                const totalSecs = Math.max(1, hi - lo);

                const BUCKETS = 24;
                const bucketSecs = totalSecs / BUCKETS;
                const counts = new Array(BUCKETS).fill(0);
                times.forEach(t => {
                    let b = Math.floor((t - lo) / bucketSecs);
                    if (b < 0) b = 0; if (b >= BUCKETS) b = BUCKETS - 1;
                    counts[b]++;
                });
                const peak = Math.max.apply(null, counts) || 1;

                let bars = '<div class="timeline">';
                counts.forEach(n => {
                    const h = n === 0 ? 0 : Math.round((n / peak) * 100);
                    const cls = n === 0 ? 'timeline-bar empty' : 'timeline-bar';
                    const title = n + ' commit' + (n === 1 ? '' : 's');
                    bars += '<div class="' + cls + '" style="height:' + Math.max(h, n ? 6 : 4) + '%" title="' + title + '"></div>';
                });
                bars += '</div>';

                const axis = '<div class="timeline-axis"><span>' +
                    new Date(lo * 1000).toLocaleDateString() + '</span><span>' +
                    new Date(hi * 1000).toLocaleDateString() + '</span></div>';
                return bars + axis;
            }

            // Called by Swift once `git show` returns. Renders a lightly colorized diff.
            window.renderDiff = function (hash, diffText) {
                const slot = document.getElementById('diff-slot');
                if (!slot) return;
                slot.className = 'detail-diff';
                slot.id = '';
                slot.innerHTML = colorizeDiff(diffText);
            };

            function colorizeDiff(text) {
                return text.split('\\n').map(line => {
                    const safe = escapeHTML(line);
                    if (line.startsWith('+') && !line.startsWith('+++')) return '<span class="add">' + safe + '</span>';
                    if (line.startsWith('-') && !line.startsWith('---')) return '<span class="del">' + safe + '</span>';
                    if (line.startsWith('@@')) return '<span class="hunk">' + safe + '</span>';
                    if (line.startsWith('diff ') || line.startsWith('index ') ||
                        line.startsWith('+++') || line.startsWith('---') ||
                        line.startsWith('commit ') || line.startsWith('Author') ||
                        line.startsWith('Commit') || line.startsWith('Date')) {
                        return '<span class="meta">' + safe + '</span>';
                    }
                    return safe;
                }).join('\\n');
            }

            // ---- Search (filter/highlight) ----
            const searchBar = document.createElement('div');
            searchBar.id = 'search-bar';
            searchBar.innerHTML =
                '<input id="search-input" type="text" placeholder="Filter commits by message, author, or hash…" />' +
                '<span id="search-count"></span>' +
                '<span style="flex:1"></span>' +
                '<button id="search-done">Done</button>';
            document.body.appendChild(searchBar);

            const searchInput = document.getElementById('search-input');
            const searchCount = document.getElementById('search-count');

            function openSearch() {
                searchBar.classList.add('open');
                searchInput.focus();
                searchInput.select();
            }
            function closeSearch() {
                searchBar.classList.remove('open');
                applyFilter('');
                searchInput.value = '';
            }
            document.getElementById('search-done').addEventListener('click', closeSearch);

            function applyFilter(q) {
                q = q.trim().toLowerCase();
                const rows = list.querySelectorAll('.commit-row');
                if (!q) {
                    rows.forEach(r => r.classList.remove('dimmed', 'match'));
                    searchCount.textContent = '';
                    return;
                }
                let matches = 0;
                rows.forEach(r => {
                    const c = commits[+r.dataset.index];
                    const hit =
                        c.subject.toLowerCase().includes(q) ||
                        c.authorName.toLowerCase().includes(q) ||
                        c.hash.toLowerCase().includes(q) ||
                        c.body.toLowerCase().includes(q);
                    r.classList.toggle('dimmed', !hit);
                    r.classList.toggle('match', hit);
                    if (hit) matches++;
                });
                searchCount.textContent = matches + ' match' + (matches === 1 ? '' : 'es');
            }

            searchInput.addEventListener('input', () => applyFilter(searchInput.value));
            searchInput.addEventListener('keydown', (e) => {
                if (e.key === 'Escape') { closeSearch(); }
                else if (e.key === 'Enter') {
                    const first = list.querySelector('.commit-row.match');
                    if (first) first.scrollIntoView({ block: 'center', behavior: 'smooth' });
                }
            });

            // Keyboard: ⌘F search, Esc closes panel/search.
            document.addEventListener('keydown', (e) => {
                if ((e.metaKey || e.ctrlKey) && e.key === 'f') {
                    e.preventDefault();
                    openSearch();
                } else if (e.key === 'Escape') {
                    if (panel.classList.contains('open')) closeDetail();
                    else if (searchBar.classList.contains('open')) closeSearch();
                }
            });

            // Expose for the native menu (⌘F item, reload uses native reload).
            window.gitGraph = { openSearch: openSearch, closeSearch: closeSearch };

            // ---- Helpers ----
            function escapeHTML(s) {
                if (s == null) return '';
                return String(s)
                    .replace(/&/g, '&amp;')
                    .replace(/</g, '&lt;')
                    .replace(/>/g, '&gt;')
                    .replace(/"/g, '&quot;')
                    .replace(/'/g, '&#39;');
            }

            function relativeTime(unixSeconds) {
                const now = GRAPH_DATA.now || (Math.floor(Date.now() / 1000));
                let s = Math.max(0, now - unixSeconds);
                const units = [
                    ['year', 31536000], ['month', 2592000], ['week', 604800],
                    ['day', 86400], ['hour', 3600], ['minute', 60]
                ];
                for (const [name, secs] of units) {
                    const v = Math.floor(s / secs);
                    if (v >= 1) return v + ' ' + name + (v === 1 ? '' : 's') + ' ago';
                }
                return 'just now';
            }
        })();
        """
    }

    // MARK: - Error / fallback screens

    static func generateErrorHTML(error: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>git-graph</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
                    display: flex; align-items: center; justify-content: center;
                    height: 100vh; margin: 0; background-color: #f6f8fa; color: #24292f;
                }
                @media (prefers-color-scheme: dark) {
                    body { background-color: #0d1117; color: #c9d1d9; }
                }
                .error-box { text-align: center; padding: 40px; max-width: 460px; }
                .error-icon { font-size: 48px; margin-bottom: 16px; }
                h2 { font-weight: 600; }
                .error-message {
                    color: #cf222e; font-size: 14px; font-family: "SF Mono", monospace;
                    background: rgba(248,81,73,0.1); padding: 12px 16px; border-radius: 8px; margin-top: 16px;
                }
                @media (prefers-color-scheme: dark) { .error-message { color: #ff7b72; } }
            </style>
        </head>
        <body>
            <div class="error-box">
                <div class="error-icon">⚠️</div>
                <h2>Unable to render git graph</h2>
                <div class="error-message">\(error.htmlEscaped)</div>
            </div>
        </body>
        </html>
        """
    }
}

private extension String {
    /// Minimal escape for embedding in the error screen.
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
