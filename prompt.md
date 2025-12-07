This is an app to learn motor skills. 

# From my research

Most SRS apps do not track physical performance or “motor-skill mastery.”

They don’t log things like “my speed/accuracy improved” or “my form was correct” — which are crucial for motor skills.

Because of that, using a standard SRS app for motor skills means you’d be responsible for: 

1. doing the practice
2. self-evaluating performance
3. adjusting difficulty manually
4. adjusting repetition scheduling manually

The optimal spacing intervals for motor skills are substantially longer than for memorization:

Initial learning: 24-48 hour intervals
Skill development: Weekly reviews
Maintenance: Monthly or even quarterly sessions
This contrasts sharply with verbal learning, where intervals of just hours or days suffice. Research consistently shows that cross-day distribution (spacing practice sessions across different days) vastly outperforms within-day spacing.

## The Sleep Advantage: Why Evening Practice Works
Sleep transforms practice into permanent skill. Sleep-dependent consolidation can actually improve performance beyond the level achieved during practice, with studies showing that training in the evening (close to sleep) produces superior retention compared to morning training (Duke et al., 2009).

The mechanism involves synchronized reactivation of the striatum and cerebellum during sleep, with motor cortex representations becoming more efficient after overnight consolidation. For guitarists, this means practicing a challenging passage before sleep and returning to it the next day often yields dramatic improvement without additional practice.

## Practical Sleep Strategies
Complex skills (scale navigation, intricate fingerpicking): Require 24+ hours consolidation
Simple skills (basic chord changes): 12 hours often sufficient
Evening practice bonus: Training close to sleep produces superior retention
Mental rehearsal counts: Visualizing during rest periods enhances consolidation
Interleaved Practice: The Contextual Interference Effect
The contextual interference effect shows that random or interleaved practice produces better learning than blocked practice, despite feeling harder. Meta-analyses reveal medium effect sizes (d=0.54) for random practice (Shea & Morgan, 1979), with the benefit increasing dramatically for older adults (d=1.28).

Carter and Grahn's (2016) study of advanced clarinetists found that alternating 3-minute blocks between pieces produced superior retention compared to 12-minute continuous blocks. For guitarists, this means:

Practice scales in random rather than sequential keys
Alternate between different chord progressions
Mix technical exercises with repertoire work
Switch between pieces every 3-4 minutes
This approach also reduces repetitive strain injury risk (which affects over 60% of musicians) by varying physical demands across different muscle groups.

## The 80/20 Rule for Practice Allocation
Research supports allocating your practice time strategically:

50% new material and technical development
33-50% spaced repetition review of existing repertoire
10-15% theory, ear training, and improvisation
This ensures continuous progress while maintaining your existing skills. The key is that your review sessions should follow spaced intervals, not daily repetition of everything you know.

## Common Mistakes That Sabotage Spaced Repetition

1. Starting Too Many Skills at Once
Problem: Cognitive overload prevents proper consolidation

Solution: Begin with 3-5 skills maximum, add new ones only as others become automatic

2. Ignoring the "Desirable Difficulty"
Problem: Reviewing too soon (before forgetting begins) reduces benefit

Solution: Wait until recall requires effort—that struggle signals effective learning

3. Using Within-Day Spacing
Problem: Multiple sessions in one day show minimal benefit for motor skills

Solution: Always space across different days for motor learning

4. Abandoning the System Too Early
Problem: Benefits compound over months, not days

Solution: Commit to at least 2-3 months before evaluating results

5. Not Adjusting for Individual Differences
Problem: Optimal intervals vary between individuals

Solution: Track your personal forgetting curve and adjust accordingly



# Goal of the app

An app specifically for guitar playing motor skills. Start with just the task of switching between two chords. Each cord combination is a separate "card", that will contain:
- name (e.g. "Chord switching: C and D")
- BPM for current level that the user can consistantly comfortable master
- BPM for current level that the user mostly masters
- BPM where the user struggles

The goal is to train each part a short while (see above on research), and in the order above. Then move on to the next item.

Use spaced repetition logic to prioritize weak spots in the training, but also keep some randomness to make sure no card gets neglected. We assume that the user does not have time to review all cards in a single day. 

Start with the basic chords of A, B, C, D, E, F, G, Am, Em, which should be created if not existing on startup. These cards should be put in a "deck" called "Chords". Each card must belong to a deck.

To make this feature work, a metronome feature also needs to be integrated into the app where the user can tap to increase/decrease BMP by steps of 10. These values should then be stored in the card.