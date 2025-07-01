import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

def plot_relative_imbalance():
    # Read the CSV file
    df = pd.read_csv('Results/relative_imbalance_data.csv')

    # Clients are sorted by their demand
    plot_order = ['A', 'G', 'F', 'I', 'Q', 'S', 'K', 'H','U', 'L', 'Y','T','O','J', 'V', 'N', 'W' ]

    allocation_labels = {
        "shapley": ("Shapley", "red"),
        "VCG": ("VCG", "yellow"),
        "VCG_budget_balanced": ("VCG Budget Balanced", "orange"),
        "gately_daily": ("Gately Daily", "grey"),
        #"gately_daily": ("Gately Daily", "black"),
        "gately_interval": ("Gately 15Min interval", "lightgrey"),
        "full_cost": ("Full Cost", "pink"),
        #"reduced_cost": ("Reduced Cost", "lightblue"),
        "nucleolus": ("Nucleolus", "green")
    }

    scenarios = df['Scenario'].unique()
    fig, axes = plt.subplots(2, 2, figsize=(14, 8), sharey=True)
    axes = axes.flatten()

    # Prepare custom legend handles
    legend_handles = []
    legend_labels = []
    for key, (label, color) in allocation_labels.items():
        legend_handles.append(Line2D([0], [0], marker='o', color='w', markerfacecolor=color, markersize=8, label=label))
        legend_labels.append(label)
    # Remove y=0 from the legend, only add Average Relative Imbalance line
    legend_handles.append(Line2D([0], [1], color='blue', linewidth=2, linestyle='--', label='Average Relative Imbalance'))
    legend_labels.append('Average Relative Imbalance')

    for i, scenario in enumerate(scenarios):
        ax = axes[i]
        data = df[df['Scenario'] == scenario]
        # Ensure clients are sorted according to plot_order
        data['Client'] = pd.Categorical(data['Client'], categories=plot_order, ordered=True)
        data = data.sort_values('Client')
        ax.grid(True, zorder=0)
        ax.axhline(0, color='black', linewidth=3)  # Add horizontal line at y=0
        # Plot AverageRelativeImbalance as a horizontal line
        avg_rel_imb = data['AverageRelativeImbalance'].iloc[0]
        ax.axhline(avg_rel_imb, color='blue', linewidth=2, linestyle='--', label='Average Relative Imbalance', zorder=1.5)
        for alloc in data['Allocation'].unique():
            alloc_data = data[data['Allocation'] == alloc]
            label, color = allocation_labels.get(alloc, (alloc, None))
            ax.scatter(alloc_data['Client'], alloc_data['Value'], label=label, color=color, zorder=2, alpha=0.8)
        ax.set_title(scenario)
        ax.set_xlabel('Client')
        ax.set_ylabel('Relative Imbalance')
        ax.tick_params(axis='x', rotation=45)
        # Ensure y-axis is visible for all subplots
        ax.yaxis.set_visible(True)

    # Add a single shared legend below the plots using custom handles
    fig.legend(
        handles=legend_handles, labels=legend_labels,
        loc='lower center', bbox_to_anchor=(0.5, -0.01), ncol=len(legend_handles), frameon=True
    )
    # Move plots closer together
    plt.subplots_adjust(left=0.08, right=0.98, bottom=0.1, top=0.92, wspace=0.06, hspace=0.32)
    plt.savefig('Results/relative_imbalance.svg', bbox_inches='tight')
    plt.show()

def plot_excess():
    df = pd.read_csv('Results/excess_data.csv')
    allocation_labels = {
        "shapley": ("Shapley", "red"),
        "VCG": ("VCG", "yellow"),
        "VCG_budget_balanced": ("VCG Budget Balanced", "orange"),
        "gately_full": ("Gately Full", "grey"),
        #"gately_daily": ("Gately Daily", "black"),
        "gately_hourly": ("Gately Hourly", "lightgrey"),
        "full_cost": ("Full Cost", "pink"),
        #"reduced_cost": ("Reduced Cost", "lightblue"),
        "nucleolus": ("Nucleolus", "green")
    }
    scenarios = df['Scenario'].unique()
    fig, axes = plt.subplots(2, 2, figsize=(14, 8), sharey=True)
    axes = axes.flatten()
    legend_handles = []
    legend_labels = []
    for key, (label, color) in allocation_labels.items():
        legend_handles.append(Line2D([0], [0], marker='o', color='w', markerfacecolor=color, markersize=8, label=label))
        legend_labels.append(label)
    for i, scenario in enumerate(scenarios):
        ax = axes[i]
        data = df[df['Scenario'] == scenario]
        for alloc in data['Allocation'].unique():
            alloc_data = data[data['Allocation'] == alloc]
            label, color = allocation_labels.get(alloc, (alloc, None))
            ax.scatter([label], alloc_data['MaxInstability'], label=label, color=color, zorder=2, alpha=0.8)
        ax.set_title(scenario)
        ax.set_xlabel('Allocation')
        ax.set_ylabel('Max Instability')
        ax.tick_params(axis='x', rotation=45)
    fig.legend(
        handles=legend_handles, labels=legend_labels,
        loc='lower center', bbox_to_anchor=(0.5, -0.01), ncol=len(legend_handles), frameon=True
    )
    plt.subplots_adjust(left=0.08, right=0.98, bottom=0.1, top=0.92, wspace=0.06, hspace=0.32)
    plt.savefig('Results/excess_plot.svg', bbox_inches='tight')
    plt.show()


if __name__ == "__main__":
    plot_relative_imbalance()
    #plot_excess()
    

